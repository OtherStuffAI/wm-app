package com.wingmanbefree.wingman_app.grasp

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GraspMessagePolicyTest {
    @Test fun `grasp accepts only the HTTPS current main frame`() {
        assertTrue(GraspMessagePolicy.accepts("WingmanGrasp", true, "https://app.example", "https://app.example/path"))
        assertTrue(GraspMessagePolicy.accepts("WingmanGrasp", true, "https://app.example:443", "https://app.example/path"))
        assertFalse(GraspMessagePolicy.accepts("WingmanGrasp", false, "https://app.example", "https://app.example"))
        assertFalse(GraspMessagePolicy.accepts("WingmanGrasp", true, "https://evil.example", "https://app.example"))
        assertFalse(GraspMessagePolicy.accepts("WingmanGrasp", true, "https://app.example:444", "https://app.example"))
        assertFalse(GraspMessagePolicy.accepts("WingmanGrasp", true, "https://app.example", "http://app.example"))
        assertFalse(GraspMessagePolicy.accepts("WingmanGrasp", true, "http://app.example", "http://app.example"))
    }

    @Test fun `signer and tower reject iframe spoofing but preserve HTTP top frames`() {
        for (name in listOf("WingmanSigner", "WingmanTower")) {
            assertTrue(GraspMessagePolicy.accepts(name, true, "http://localhost:8080", "http://localhost:8080/app"))
            assertFalse(GraspMessagePolicy.accepts(name, false, "https://app.example", "https://app.example"))
            assertFalse(GraspMessagePolicy.accepts(name, true, "https://evil.example", "https://app.example"))
        }
    }

    @Test fun `opaque malformed credentialed and missing origins fail closed`() {
        for (url in listOf("null", "about:blank", "file:///app", "data:text/html,test", "https://user@app.example", "https://app.example:99999", "")) {
            assertFalse(url, GraspMessagePolicy.accepts("WingmanGrasp", true, url, url))
        }
        assertFalse(GraspMessagePolicy.accepts("WingmanGrasp", true, "https://app.example", null))
        assertFalse(GraspMessagePolicy.accepts("Unknown", true, "https://app.example", "https://app.example"))
    }
}
