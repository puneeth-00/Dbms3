const express = require('express');
const path = require('path');
const db = require('./database/db');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;

// Setup Middleware
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.use(express.static(path.join(__dirname, 'public')));
app.use(express.urlencoded({ extended: true }));
app.use(express.json());

// ==========================================
// 1. DASHBOARD / HOME ROUTE
// ==========================================
app.get('/', async (req, res) => {
    try {
        const statsQuery = `
            SELECT 
                (SELECT COUNT(*) FROM students) AS student_count,
                (SELECT COUNT(*) FROM departments) AS dept_count,
                (SELECT COUNT(*) FROM certificate_requests) AS total_requests,
                (SELECT COUNT(*) FROM certificate_requests WHERE status = 'PENDING') AS pending_requests,
                (SELECT COUNT(*) FROM certificates_issued) AS issued_count,
                (SELECT COUNT(*) FROM verification_logs) AS verification_count
        `;
        const statsRes = await db.query(statsQuery);

        const recentRequestsQuery = `
            SELECT cr.request_id, s.full_name, s.reg_number, ct.title AS cert_title, cr.requested_at, cr.status
            FROM certificate_requests cr
            JOIN students s ON cr.student_id = s.student_id
            JOIN certificate_types ct ON cr.cert_type_id = ct.cert_type_id
            ORDER BY cr.requested_at DESC
            LIMIT 5
        `;
        const recentRes = await db.query(recentRequestsQuery);

        const certTypesRes = await db.query('SELECT * FROM certificate_types ORDER BY processing_fee ASC');

        res.render('index', {
            title: 'Dashboard',
            activeTab: 'home',
            stats: statsRes.rows[0],
            recentRequests: recentRes.rows,
            certTypes: certTypesRes.rows,
        });
    } catch (err) {
        console.error('Error loading dashboard:', err);
        res.status(500).send('Database connection error. Ensure PostgreSQL is running and DB is initialized.');
    }
});

// ==========================================
// 2. STUDENT PORTAL (APPLY & TRACK)
// ==========================================
app.get('/students', async (req, res) => {
    try {
        const studentsRes = await db.query(`
            SELECT s.*, d.dept_code, d.dept_name 
            FROM students s 
            JOIN departments d ON s.department_id = d.department_id 
            ORDER BY s.student_id ASC
        `);
        const certTypesRes = await db.query('SELECT * FROM certificate_types WHERE is_active = TRUE ORDER BY title ASC');
        const requestsRes = await db.query(`
            SELECT cr.*, s.full_name, s.reg_number, ct.title AS cert_title, ct.processing_fee
            FROM certificate_requests cr
            JOIN students s ON cr.student_id = s.student_id
            JOIN certificate_types ct ON cr.cert_type_id = ct.cert_type_id
            ORDER BY cr.requested_at DESC
        `);

        res.render('students', {
            title: 'Student Portal',
            activeTab: 'students',
            students: studentsRes.rows,
            certTypes: certTypesRes.rows,
            requests: requestsRes.rows,
            error: req.query.error || null,
            success: req.query.success || null,
        });
    } catch (err) {
        console.error('Error loading student portal:', err);
        res.status(500).send('Database error.');
    }
});

// Submit a new certificate request (Demonstrates Trigger 2: Duplicate check)
app.post('/students/request', async (req, res) => {
    const { student_id, cert_type_id, purpose } = req.body;
    try {
        await db.query(
            `INSERT INTO certificate_requests (student_id, cert_type_id, purpose) VALUES ($1, $2, $3)`,
            [student_id, cert_type_id, purpose]
        );
        res.redirect('/students?success=Certificate request submitted successfully for university review!');
    } catch (err) {
        console.error('Trigger caught or database error:', err.message);
        // Extracts trigger exception message cleanly
        const errorMsg = encodeURIComponent(err.message.replace('error: ', ''));
        res.redirect(`/students?error=${errorMsg}`);
    }
});

// ==========================================
// 3. REGISTRAR / ADMIN OFFICE (STORED PROCEDURES)
// ==========================================
app.get('/admin', async (req, res) => {
    try {
        const pendingQuery = `
            SELECT cr.*, s.full_name, s.reg_number, d.dept_name, ct.title AS cert_title, ct.processing_fee
            FROM certificate_requests cr
            JOIN students s ON cr.student_id = s.student_id
            JOIN departments d ON s.department_id = d.department_id
            JOIN certificate_types ct ON cr.cert_type_id = ct.cert_type_id
            WHERE cr.status = 'PENDING'
            ORDER BY cr.requested_at ASC
        `;
        const pendingRes = await db.query(pendingQuery);

        const issuedQuery = `
            SELECT ci.*, cr.request_id, s.full_name, s.reg_number, ct.title AS cert_title
            FROM certificates_issued ci
            JOIN certificate_requests cr ON ci.request_id = cr.request_id
            JOIN students s ON cr.student_id = s.student_id
            JOIN certificate_types ct ON cr.cert_type_id = ct.cert_type_id
            ORDER BY ci.issued_id DESC
        `;
        const issuedRes = await db.query(issuedQuery);

        res.render('admin', {
            title: 'Registrar Office',
            activeTab: 'admin',
            pendingRequests: pendingRes.rows,
            issuedCerts: issuedRes.rows,
            error: req.query.error || null,
            success: req.query.success || null,
        });
    } catch (err) {
        console.error('Error loading admin portal:', err);
        res.status(500).send('Database error.');
    }
});

// Approve & Issue Certificate via Stored Procedure sp_approve_and_issue_certificate
app.post('/admin/approve', async (req, res) => {
    const { request_id, officer_name } = req.body;
    try {
        // CALL Stored Procedure
        await db.query(
            `CALL sp_approve_and_issue_certificate($1, $2, $3)`,
            [request_id, 'Approved and processed by administrative registrar.', officer_name || 'Dean of Academic Affairs']
        );
        res.redirect('/admin?success=Stored Procedure executed: Certificate successfully issued and tamper hash recorded!');
    } catch (err) {
        console.error('Error executing procedure:', err.message);
        res.redirect(`/admin?error=${encodeURIComponent(err.message)}`);
    }
});

// Reject Request via Stored Procedure sp_reject_request
app.post('/admin/reject', async (req, res) => {
    const { request_id } = req.body;
    try {
        await db.query(
            `CALL sp_reject_request($1, $2)`,
            [request_id, 'Eligibility criteria not met or documents incomplete.']
        );
        res.redirect('/admin?success=Request marked as rejected in the database.');
    } catch (err) {
        console.error('Error rejecting request:', err.message);
        res.redirect(`/admin?error=${encodeURIComponent(err.message)}`);
    }
});

// ==========================================
// 4. PUBLIC VERIFICATION PORTAL (AUDIT LOGS)
// ==========================================
app.get('/verify', async (req, res) => {
    try {
        const certNumber = req.query.cert || null;
        let result = null;

        if (certNumber) {
            const checkQuery = `
                SELECT ci.*, s.full_name, s.reg_number, d.dept_name, ct.title AS cert_title
                FROM certificates_issued ci
                JOIN certificate_requests cr ON ci.request_id = cr.request_id
                JOIN students s ON cr.student_id = s.student_id
                JOIN departments d ON s.department_id = d.department_id
                JOIN certificate_types ct ON cr.cert_type_id = ct.cert_type_id
                WHERE ci.cert_number = $1
            `;
            const checkRes = await db.query(checkQuery, [certNumber.trim()]);
            if (checkRes.rowCount > 0) {
                result = { isValid: true, data: checkRes.rows[0] };
            } else {
                result = { isValid: false, data: null };
            }
        }

        const logsRes = await db.query(`SELECT * FROM verification_logs ORDER BY verified_at DESC LIMIT 10`);

        res.render('verify', {
            title: 'Certificate Verification',
            activeTab: 'verify',
            queriedCert: certNumber,
            result,
            logs: logsRes.rows,
        });
    } catch (err) {
        console.error('Error loading verify page:', err);
        res.status(500).send('Database error.');
    }
});

// Handle Verification Form Submission (Records to verification_logs)
app.post('/verify', async (req, res) => {
    const { cert_number, verifier_name, verifier_org } = req.body;
    try {
        const cleanCert = cert_number ? cert_number.trim() : '';
        const checkQuery = `
            SELECT ci.*, s.full_name, s.reg_number, d.dept_name, ct.title AS cert_title
            FROM certificates_issued ci
            JOIN certificate_requests cr ON ci.request_id = cr.request_id
            JOIN students s ON cr.student_id = s.student_id
            JOIN departments d ON s.department_id = d.department_id
            JOIN certificate_types ct ON cr.cert_type_id = ct.cert_type_id
            WHERE ci.cert_number = $1
        `;
        const checkRes = await db.query(checkQuery, [cleanCert]);
        const isValid = checkRes.rowCount > 0;
        const verificationResult = isValid ? 'VALID' : 'INVALID';

        // Insert into verification_logs table for audit compliance
        await db.query(
            `INSERT INTO verification_logs (cert_number_queried, verifier_name, verifier_org, verification_result)
             VALUES ($1, $2, $3, $4)`,
            [cleanCert, verifier_name, verifier_org, verificationResult]
        );

        const logsRes = await db.query(`SELECT * FROM verification_logs ORDER BY verified_at DESC LIMIT 10`);

        res.render('verify', {
            title: 'Certificate Verification',
            activeTab: 'verify',
            queriedCert: cleanCert,
            result: {
                isValid,
                data: isValid ? checkRes.rows[0] : null,
            },
            logs: logsRes.rows,
        });
    } catch (err) {
        console.error('Error during verification:', err);
        res.status(500).send('Verification processing error.');
    }
});

// ==========================================
// 5. PRINTABLE CERTIFICATE VIEW
// ==========================================
app.get('/certificate/:requestId', async (req, res) => {
    try {
        const certQuery = `
            SELECT ci.*, s.full_name, s.reg_number, d.dept_name, ct.title AS cert_title
            FROM certificates_issued ci
            JOIN certificate_requests cr ON ci.request_id = cr.request_id
            JOIN students s ON cr.student_id = s.student_id
            JOIN departments d ON s.department_id = d.department_id
            JOIN certificate_types ct ON cr.cert_type_id = ct.cert_type_id
            WHERE cr.request_id = $1
        `;
        const certRes = await db.query(certQuery, [req.params.requestId]);
        if (certRes.rowCount === 0) {
            return res.status(404).send('Certificate not found or not yet issued.');
        }

        res.render('certificate', {
            title: 'Official Academic Certificate',
            activeTab: 'students',
            cert: certRes.rows[0],
        });
    } catch (err) {
        console.error('Error loading certificate:', err);
        res.status(500).send('Error loading certificate.');
    }
});


// Start Server
app.listen(PORT, () => {
    console.log(`====================================================`);
    console.log(`🚀 EduVerify DBMS Web Application is running!`);
    console.log(`🌐 Local URL: http://localhost:${PORT}`);
    console.log(`====================================================`);
});
