# 🛠️ Asha Grill House App

A custom-built, offline-first mobile application designed specifically to manage the daily operations of **Asha Grill House**, an iron and steel fabrication business located in Muragachha.

Owned and operated by **Biggyan Das**, this app streamlines customer management, order tracking, measurements, financial accounting, and expenses, all from a mobile device.

## ✨ Key Features

### 👥 Customer & Order Management

* **Customer Directory:** Add and manage customer profiles and contact details.

* **Measurement Tracking (মাপ):** Record and store specific geometrical measurements for custom fabrication orders.

* **Order Page:** Keep track of active and completed fabrication jobs.

### 💰 Financial Tracking & Accounting

* **Ledger / Hisab (হিসাব):** Monitor customer credit, pending dues, and complete transaction histories.

* **Expense Management (খরচ):** Track daily shop expenses to calculate net profitability.

* **Payments:** Seamlessly record incoming payments and generate receipts.

### ☁️ Smart Cloud Backup & Offline-First Architecture

* **Local First:** Operates entirely offline using an on-device SQLite database, ensuring lightning-fast load times and zero dependency on a constant internet connection.

* **Action-Triggered Sync:** Cloud backups (via Google Apps Script to Google Sheets) are strictly triggered by user actions (adding, editing, or deleting data) rather than on app startup. This optimizes Google API usage, saves mobile data, and dramatically improves app launch speeds.

* **Data Management:** Built-in tools for manual **Import**, **Export**, and checking **Backup Status**.

### 🧰 Advanced Utilities

* **Geometry Calculator:** A built-in tool customized for iron/steel fabrication calculations.

* **Database Studio:** Direct in-app database inspection for administrative debugging.

* **Customer Feedback:** A dedicated portal to log customer reviews and feedback.

* **Factory Reset (Dismantle):** Securely wipe local data when provisioning a new device or cleaning the system.

* **Deep Linking:** Supports deep links (e.g., `/admin`) to open the app directly to specific administrative views.

## 🛠️ Tech Stack

* **Frontend:** [Flutter](https://flutter.dev/) (Dart)

* **Local Database:** SQLite

* **Cloud Backend:** Google Apps Script / Google Sheets API (used as a free, accessible cloud database)

* **Routing:** `app_links` for deep linking

* **UI/UX:** Custom modern styling with a custom `BottomNavigationBar`, deep orange branding, and intuitive drawer menus.

## 📱 App Structure

The app features a unified bottom navigation bar for quick access to the most used modules:

1. **হোম (Home):** Dashboard and quick actions.

2. **হিসাব (Accounts):** Financial overviews and dues.

3. **মাপ (Measurements):** Active job dimensions.

4. **খরচ (Expenses):** Daily operational costs.

The **Modern Navigation Drawer** provides access to deeper administrative tools like Reports, Documentation, Configuration, and the Database Studio.

## 🚀 Getting Started

### Prerequisites

* Flutter SDK (Latest stable release)

* Dart SDK

* A connected Android/iOS device or emulator

### Installation

1. Clone the repository:

   ```
   git clone https://github.com/yourusername/asha-grill-house.git
   
   ```

2. Navigate to the project directory:

   ```
   cd asha-grill-house
   
   ```

3. Install dependencies:

   ```
   flutter pub get
   
   ```

4. Run the app:

   ```
   flutter run
   
   ```

## 👨‍💻 Author

**Developed for:** Asha Grill House (Biggyan Das)

**Established:** 2015

**Contact:** 9932134803

*Quality iron and steel fabrication in Muragachha with fair pricing, durable design, and on-time service.*
