import docx
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

def create_doc():
    doc = docx.Document()
    
    # Title
    title = doc.add_heading('Invisiguard Frontend & Backend Connectivity', 0)
    title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    
    # Introduction
    doc.add_heading('1. Overview', level=1)
    doc.add_paragraph(
        "This document illustrates the communication and connectivity flow between the Invisiguard "
        "Frontend (Flutter Mobile App) and Backend (Firebase Realtime Database & Python Inference Service)."
    )
    
    # Block Diagram
    doc.add_heading('2. Connectivity Block Diagram', level=1)
    
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run(
        "            [ FRONTEND ]                            [ BACKEND ]\n"
        "                                                         \n"
        " +--------------------------+           +--------------------------+\n"
        " |                          |           |                          |\n"
        " |    Flutter Mobile App    |           |    Python Inference      |\n"
        " |   (Guardian Interface)   |           |         Service          |\n"
        " |                          |           |                          |\n"
        " +--------------------------+           +--------------------------+\n"
        "          |       ^                               ^       |\n"
        "          | Push  | Listen &                      | Pull  | Push\n"
        "          | User  | Fetch Alert                   | Sens- | ML Pred-\n"
        "          | Config| Status & Map                  | or    | ictions &\n"
        "          |       | History                       | Data  | Alerts\n"
        "          v       |                               |       v\n"
        "       +------------------------------------------------------+\n"
        "       |                                                      |\n"
        "       |            Firebase Realtime Database                |\n"
        "       |           (Cloud Messaging & Storage)                |\n"
        "       |                                                      |\n"
        "       +------------------------------------------------------+\n"
        "                               ^       \n"
        "                               | Push  \n"
        "                               | Sensor\n"
        "                               | Data  \n"
        "                   +------------------------+\n"
        "                   |   Wearable IoT Node    |\n"
        "                   +------------------------+\n"
    )
    run.font.name = 'Courier New'
    run.font.size = Pt(9)
    
    # Component Connectivity Descriptions
    doc.add_heading('3. Connectivity Breakdown', level=1)
    
    doc.add_heading('A. Frontend (Flutter App) <-> Firebase', level=2)
    doc.add_paragraph(
        "- The Flutter app maintains a persistent real-time connection to Firebase via WebSockets.\n"
        "- It continually listens to changes in the '/student' node, specifically for the 'is_alert' or 'ml_alert' flags.\n"
        "- When the backend updates these flags, the change is pushed instantly to the app to trigger UI alerts.\n"
        "- The app also periodically fetches and writes location history data to Firebase for the map view."
    )
    
    doc.add_heading('B. Backend (Python Service) <-> Firebase', level=2)
    doc.add_paragraph(
        "- The Python Service acts as the intelligence layer, connecting to Firebase using the Firebase Admin SDK (Service Account Key).\n"
        "- It polls or streams data from the sensor nodes continuously.\n"
        "- After running the data through ML models, it writes the predictions ('ml_fall_probability', 'ml_motion_prediction') back to the same Firebase node.\n"
        "- If a fall is confirmed, it updates the 'is_alert' flag, which Firebase then broadcasts to the connected Frontend app."
    )
    
    doc.add_heading('C. The Role of Firebase', level=2)
    doc.add_paragraph(
        "Firebase Realtime Database bridges the gap. The Python backend and Flutter frontend never communicate directly via HTTP requests or REST APIs. Instead, they interact entirely by reading and mutating shared JSON tree states within Firebase, ensuring low latency and native real-time synchronization out of the box."
    )
    
    doc.save('Invisiguard_Frontend_Backend_Connectivity.docx')
    print("Word file created successfully.")

if __name__ == '__main__':
    create_doc()
