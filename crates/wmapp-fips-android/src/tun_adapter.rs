use crate::dns_proxy;
use fips::upper::{icmp::effective_ipv6_mtu, tcp_mss::clamp_tcp_mss};
use std::fs::File;
use std::io::{Read, Write};
use std::net::SocketAddr;
use std::os::fd::{FromRawFd, RawFd};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread::JoinHandle;
use std::time::Duration;

const TUN_MTU: usize = 1280;

pub(crate) fn is_mesh_ipv6(packet: &[u8]) -> bool {
    packet.len() >= 40 && packet[0] >> 4 == 6 && packet[24] == 0xfd
}

pub(crate) fn clamp_outbound(packet: &mut [u8], transport_mtu: u16) -> bool {
    let max_mss = effective_ipv6_mtu(transport_mtu).saturating_sub(60);
    clamp_tcp_mss(packet, max_mss)
}

pub(crate) struct TunAdapter {
    stop: Arc<AtomicBool>,
    fd: RawFd,
    reader: Option<JoinHandle<()>>,
    writer: Option<JoinHandle<()>>,
}

impl TunAdapter {
    pub(crate) fn start(
        fd: RawFd,
        outbound: tokio::sync::mpsc::Sender<Vec<u8>>,
        inbound: std::sync::mpsc::Receiver<Vec<u8>>,
        transport_mtu: u16,
        resolver: SocketAddr,
    ) -> std::io::Result<Self> {
        let read_fd = unsafe { libc::dup(fd) };
        let dns_write_fd = unsafe { libc::dup(fd) };
        let write_fd = unsafe { libc::dup(fd) };
        if read_fd < 0 || dns_write_fd < 0 || write_fd < 0 {
            return Err(std::io::Error::last_os_error());
        }
        let stop = Arc::new(AtomicBool::new(false));
        let reader_stop = Arc::clone(&stop);
        let reader = std::thread::Builder::new()
            .name("wm-fips-tun-in".into())
            .spawn(move || {
                let mut input = unsafe { File::from_raw_fd(read_fd) };
                let mut dns_output = unsafe { File::from_raw_fd(dns_write_fd) };
                let mut buffer = vec![0u8; TUN_MTU + 256];
                while !reader_stop.load(Ordering::Acquire) {
                    let mut descriptor = libc::pollfd {
                        fd: read_fd,
                        events: libc::POLLIN,
                        revents: 0,
                    };
                    let ready = unsafe { libc::poll(&mut descriptor, 1, 200) };
                    if ready <= 0 {
                        continue;
                    }
                    let length = match input.read(&mut buffer) {
                        Ok(0) => continue,
                        Ok(length) => length,
                        Err(_) => break,
                    };
                    let packet = &mut buffer[..length];
                    if let Some((ihl, payload)) = dns_proxy::is_fips_dns_query(packet) {
                        if let Ok(reply) = dns_proxy::proxy_query(packet, ihl, payload, resolver) {
                            let _ = dns_output.write_all(&reply);
                        }
                        continue;
                    }
                    if !is_mesh_ipv6(packet) {
                        continue;
                    }
                    clamp_outbound(packet, transport_mtu);
                    if outbound.blocking_send(packet.to_vec()).is_err() {
                        break;
                    }
                }
            })?;
        let writer_stop = Arc::clone(&stop);
        let writer = std::thread::Builder::new()
            .name("wm-fips-tun-out".into())
            .spawn(move || {
                let mut output = unsafe { File::from_raw_fd(write_fd) };
                while !writer_stop.load(Ordering::Acquire) {
                    match inbound.recv_timeout(Duration::from_millis(200)) {
                        Ok(packet) if output.write_all(&packet).is_err() => break,
                        Ok(_) | Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {}
                        Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => break,
                    }
                }
            })?;
        Ok(Self {
            stop,
            fd,
            reader: Some(reader),
            writer: Some(writer),
        })
    }

    pub(crate) fn stop(&mut self) {
        self.stop.store(true, Ordering::Release);
        if let Some(handle) = self.reader.take() {
            let _ = handle.join();
        }
        if let Some(handle) = self.writer.take() {
            let _ = handle.join();
        }
        unsafe { libc::close(self.fd) };
    }
}

impl Drop for TunAdapter {
    fn drop(&mut self) {
        self.stop();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::fd::IntoRawFd;
    use std::os::unix::net::UnixDatagram;

    fn syn_packet(mss: u16) -> Vec<u8> {
        let mut packet = vec![0u8; 64];
        packet[0] = 0x60;
        packet[6] = 6;
        packet[24] = 0xfd;
        packet[40 + 12] = 6 << 4;
        packet[40 + 13] = 0x02;
        packet[60] = 2;
        packet[61] = 4;
        packet[62..64].copy_from_slice(&mss.to_be_bytes());
        packet
    }

    #[test]
    fn admits_only_fd00_destination_ipv6() {
        let mut mesh = vec![0u8; 40];
        mesh[0] = 0x60;
        mesh[24] = 0xfd;
        let mut public = mesh.clone();
        public[24] = 0x20;
        assert!(is_mesh_ipv6(&mesh));
        assert!(!is_mesh_ipv6(&public));
        assert!(!is_mesh_ipv6(&[0x45; 40]));
    }

    #[test]
    fn clamps_outbound_syn_to_fips_safe_mss() {
        let mut packet = syn_packet(1460);
        assert!(clamp_outbound(&mut packet, 1280));
        let expected = effective_ipv6_mtu(1280) - 60;
        assert_eq!(u16::from_be_bytes([packet[62], packet[63]]), expected);
    }

    #[test]
    fn pumps_app_tun_packets_in_both_directions() {
        let (tun, app) = UnixDatagram::pair().unwrap();
        app.set_read_timeout(Some(Duration::from_secs(1))).unwrap();
        let (to_fips, mut from_tun) = tokio::sync::mpsc::channel(1);
        let (to_tun, from_fips) = std::sync::mpsc::channel();
        let resolver = "127.0.0.1:9".parse().unwrap();
        let mut adapter =
            TunAdapter::start(tun.into_raw_fd(), to_fips, from_fips, 1280, resolver).unwrap();

        let mut outbound = vec![0u8; 40];
        outbound[0] = 0x60;
        outbound[24] = 0xfd;
        app.send(&outbound).unwrap();
        assert_eq!(from_tun.blocking_recv().unwrap(), outbound);

        let inbound = vec![0x60, 0x01, 0x02, 0x03];
        to_tun.send(inbound.clone()).unwrap();
        let mut received = [0u8; 64];
        let length = app.recv(&mut received).unwrap();
        assert_eq!(&received[..length], inbound);

        adapter.stop();
    }
}
