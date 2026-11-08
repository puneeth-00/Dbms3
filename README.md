# EduVerify: Academic Certificate Request & Verification Management System

A full-stack Database Management System (DBMS) project addressing academic credential fraud and streamlining verifiable certificate issuance for colleges and universities.

Built with **PostgreSQL 18** and **Node.js (Express & EJS)**.

---

## 🎯 Societal Problem Addressed
- **The Problem:** Widespread circulation of fake degrees and credentials, lengthy manual background checks taking weeks for employers, high administrative overhead for university registrars, and risks of forged certificates.
- **The Solution:** A centralized, tamper-verifiable academic credential repository. Includes digital cryptographic hash verification, real-time employer audit logging, role-based workflows for students and registrars, and database triggers/procedures to guarantee ACID data integrity.

---

## 🏛️ Database Architecture Requirements Met

| Requirement | Implementation in EduVerify |
| :--- | :--- |
| **5+ Relational Tables** | **6 Tables**: `departments`, `students`, `certificate_types`, `certificate_requests`, `certificates_issued`, `verification_logs` |
| **At least 1 Trigger** | **2 Triggers**: <br>1. `trg_after_certificate_issued`: Automatically transitions request status to `'ISSUED'` when a certificate is recorded.<br>2. `trg_check_duplicate_pending`: Rejects duplicate pending requests for the same student and certificate type. |
| **At least 1 Stored Procedure** | **2 Stored Procedures**: <br>1. `sp_approve_and_issue_certificate`: Formats serial number, generates cryptographic hash, and inserts into issued certificates.<br>2. `sp_reject_request`: Formally marks requests as rejected with recorded justification. |
| **Web Application** | Full-featured responsive web portal with student self-service, registrar approvals, and public third-party verification portal. |
| **Societal Theme** | Educational Sector & Public Administration anti-fraud credential validation. |

---

## 🚀 Quick Start Guide

### Prerequisites
- [Node.js](https://nodejs.org/) (v16 or higher)
- [PostgreSQL](https://www.postgresql.org/) (v12 or higher)

### 1. Database Configuration
Ensure your PostgreSQL credentials in `.env` match your local PostgreSQL installation:
```env
PORT=3000
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=your_postgres_password
DB_NAME=edudb
```

### 2. Automated Database Initialization
Initialize the database, tables, triggers, stored procedures, and sample data with one command:
```bash
npm run init-db
```
*(Or double-click `setup.bat` on Windows)*

### 3. Start the Web Application
```bash
npm start
```
*(Or double-click `start.bat` on Windows)*

Visit **http://localhost:3000** in your web browser.

---

## 🌐 Application Portals
1. **Dashboard (`/`)**: High-level university metrics, active catalog, and recent request monitor.
2. **Student Portal (`/students`)**: Students apply for certificates and monitor processing stages. Demonstrates duplicate-request trigger rejection.
3. **Registrar Office (`/admin`)**: Administrative officers review pending requests and execute PostgreSQL Stored Procedures with one click.
4. **Public Verification Portal (`/verify`)**: Open to employers and foreign universities. Verifies document numbers and writes audit entries to `verification_logs`.
5. **Printable Credential (`/certificate/:id`)**: Formal certificate with institution seals, dates, and SHA256 verification fingerprints.
6. **DBMS Viva Lab (`/db-schema`)**: Visual reference with table definitions, ER structure, and trigger/procedure SQL codes.
