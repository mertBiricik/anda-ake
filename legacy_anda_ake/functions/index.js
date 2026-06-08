const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

/**
 * Triggers a "Nuclear Alarm" on the target device via FCM Data Message.
 * This bypasses the Notification Tray effectively waking the app in background.
 * 
 * Usage: Send POST request to the function URL.
 * Optional Body: { "token": "TARGET_DEVICE_TOKEN" }
 */
exports.sendNuclearAlert = functions.https.onRequest(async (req, res) => {
    // 1. Get Token from Request Query or Body (default to a hardcoded one for testing if needed)
    const targetToken = req.body.token || req.query.token;

    if (!targetToken) {
        res.status(400).send("Missing 'token' parameter. Please provide device FCM token.");
        return;
    }

    // 2. Define the NUCLEAR Payload
    // CRITICAL: We use 'data' only (or data + android priority) to ensure background handling.
    const payload = {
        token: targetToken,
        data: {
            title: "ACİL DURUM",
            body: "NÜKLEER ALARM: EKİP TOPLANIYOR",
            type: "nuclear_alarm", // Custom flag for our app logic
            mission_id: "SAR-2026-001",
            timestamp: Date.now().toString()
        },
        android: {
            priority: "high", // Forces high priority delivery
            ttl: 0 // Immediate delivery, don't buffer
        }
        // Note: NOT adding 'notification' block prevents system tray interception in some cases,
        // ensuring our background handler catches it immediately.
    };

    try {
        // 3. Send via Admin SDK
        const messageId = await admin.messaging().send(payload);
        console.log("Successfully sent nuclear alert:", messageId);
        res.status(200).json({ success: true, messageId: messageId, target: targetToken });
    } catch (error) {
        console.error("Error sending nuclear alert:", error);
        res.status(500).json({ success: false, error: error.message });
    }
});
