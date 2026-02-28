const { setGlobalOptions } = require("firebase-functions");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const logger = require("firebase-functions/logger");

admin.initializeApp();

setGlobalOptions({ maxInstances: 10 });

exports.sendAlertNotification = onDocumentCreated("users/{uid}/alerts/{alertId}", async (event) => {
    const alertData = event.data.data();
    const uid = event.params.uid;

    if (!alertData) {
        logger.log("No alert data found.");
        return;
    }

    // Fetch the user document to get the FCM token
    const userDoc = await admin.firestore().collection("users").doc(uid).get();
    if (!userDoc.exists) {
        logger.log(`User ${uid} doc does not exist.`);
        return;
    }

    const userData = userDoc.data();
    const fcmToken = userData.fcmToken;
    if (!fcmToken) {
        logger.log(`User ${uid} has no FCM token saved.`);
        return;
    }

    // Determine title based on alert type
    const alertType = (alertData.type || "ALERT").toUpperCase();
    const message = alertData.message || "An emergency alert was triggered.";
    let title = "🚨 Emergency Alert";

    if (alertType.includes("FALL")) {
        title = "🤕 Fall Detected";
    } else if (alertType.includes("SOS")) {
        title = "🚨 SOS Triggered";
    } else if (alertType.includes("GEOFENCE") || alertType.includes("EXIT")) {
        title = "📍 Geofence Alert";
    } else if (alertType.includes("BATTERY") || alertType.includes("LOW")) {
        title = "🔋 Low Battery";
    }

    const payload = {
        token: fcmToken,
        notification: {
            title: title,
            body: message,
        },
        android: {
            priority: "high",
            notification: {
                sound: "default",
                channelId: "high_importance_channel" // Good for Android O+
            }
        }
    };

    try {
        const response = await admin.messaging().send(payload);
        logger.log(`Successfully sent message to ${uid}. Message ID:`, response);
    } catch (error) {
        logger.error(`Error sending message to ${uid}:`, error);
    }
});
