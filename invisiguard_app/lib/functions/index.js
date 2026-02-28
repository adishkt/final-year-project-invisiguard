// functions/index.js - COMPLETELY FREE VERSION
const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

exports.logSOSAlert = functions.firestore
  .document('users/{userId}/alerts/{alertId}')
  .onCreate(async (snap, context) => {
    const alert = snap.data();
    
    if (alert.type !== 'SOS') return null;
    
    const userId = context.params.userId;
    const alertId = context.params.alertId;
    
    console.log(`📱 SOS Alert Created: ${alertId} for user ${userId}`);
    
    // Get emergency contacts for logging
    const contactsSnapshot = await admin.firestore()
      .collection(`users/${userId}/emergency_contacts`)
      .where('receiveAlerts', '==', true)
      .get();
    
    const contactCount = contactsSnapshot.size;
    
    // Update alert with DEMO information
    return snap.ref.update({
      'status': 'processed',
      'smsSimulation': `Would send SMS to ${contactCount} emergency contacts`,
      'totalContacts': contactCount,
      'processedAt': admin.firestore.FieldValue.serverTimestamp(),
      'note': 'In production: SMS would be sent via Twilio/TextLocal API',
      'estimatedCost': contactCount > 0 ? `₹${contactCount * 0.12}` : '₹0'
    });
  });