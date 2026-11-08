-- ====================================================================
-- PROJECT: Academic Certificate Request & Verification Management System (EduVerify)
-- DBMS: PostgreSQL 14+
-- SOCIETAL DOMAIN: Educational Sector & Anti-Fraud Credential Verification
-- ====================================================================

-- 1. DROP EXISTING OBJECTS (FOR CLEAN INITIALIZATION)
DROP TRIGGER IF EXISTS trg_after_certificate_issued ON certificates_issued;
DROP TRIGGER IF EXISTS trg_check_duplicate_pending ON certificate_requests;
DROP FUNCTION IF EXISTS fn_sync_certificate_status();
DROP FUNCTION IF EXISTS fn_prevent_duplicate_pending_request();
DROP PROCEDURE IF EXISTS sp_approve_and_issue_certificate(INT, TEXT, VARCHAR);
DROP PROCEDURE IF EXISTS sp_reject_request(INT, TEXT);

DROP TABLE IF EXISTS verification_logs CASCADE;
DROP TABLE IF EXISTS certificates_issued CASCADE;
DROP TABLE IF EXISTS certificate_requests CASCADE;
DROP TABLE IF EXISTS certificate_types CASCADE;
DROP TABLE IF EXISTS students CASCADE;
DROP TABLE IF EXISTS departments CASCADE;

-- ====================================================================
-- 2. TABLE DEFINITIONS (6 NORMALIZED RELATIONAL TABLES)
-- ====================================================================

-- Table 1: Departments
CREATE TABLE departments (
    department_id SERIAL PRIMARY KEY,
    dept_code VARCHAR(10) NOT NULL UNIQUE,
    dept_name VARCHAR(100) NOT NULL,
    head_of_dept VARCHAR(100),
    contact_email VARCHAR(120) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Table 2: Students
CREATE TABLE students (
    student_id SERIAL PRIMARY KEY,
    reg_number VARCHAR(20) NOT NULL UNIQUE,  -- e.g., USN or Roll Number
    full_name VARCHAR(120) NOT NULL,
    email VARCHAR(120) NOT NULL UNIQUE,
    phone VARCHAR(15),
    department_id INT NOT NULL,
    admission_year INT NOT NULL CHECK (admission_year >= 2000),
    graduation_year INT CHECK (graduation_year >= admission_year),
    academic_status VARCHAR(20) DEFAULT 'ACTIVE' CHECK (academic_status IN ('ACTIVE', 'GRADUATED', 'ALUMNI', 'SUSPENDED')),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_students_department FOREIGN KEY (department_id) 
        REFERENCES departments(department_id) ON DELETE RESTRICT
);

-- Table 3: Certificate Types (Catalog of verifiable certificates)
CREATE TABLE certificate_types (
    cert_type_id SERIAL PRIMARY KEY,
    code VARCHAR(20) NOT NULL UNIQUE,
    title VARCHAR(100) NOT NULL,
    description TEXT,
    processing_fee NUMERIC(8, 2) DEFAULT 0.00 CHECK (processing_fee >= 0),
    sla_days INT DEFAULT 3 CHECK (sla_days >= 1),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Table 4: Certificate Requests (Requests submitted by students)
CREATE TABLE certificate_requests (
    request_id SERIAL PRIMARY KEY,
    student_id INT NOT NULL,
    cert_type_id INT NOT NULL,
    purpose TEXT NOT NULL,
    supporting_doc_ref VARCHAR(255),
    status VARCHAR(20) DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED', 'ISSUED')),
    admin_remarks TEXT,
    requested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_requests_student FOREIGN KEY (student_id) 
        REFERENCES students(student_id) ON DELETE CASCADE,
    CONSTRAINT fk_requests_cert_type FOREIGN KEY (cert_type_id) 
        REFERENCES certificate_types(cert_type_id) ON DELETE RESTRICT
);

-- Table 5: Certificates Issued (Official generated tamper-verifiable credentials)
CREATE TABLE certificates_issued (
    issued_id SERIAL PRIMARY KEY,
    request_id INT NOT NULL UNIQUE,
    cert_number VARCHAR(40) NOT NULL UNIQUE,       -- e.g., EDU-2026-CS-0001
    verification_hash VARCHAR(64) NOT NULL UNIQUE, -- SHA256 digital fingerprint
    issued_by VARCHAR(100) NOT NULL DEFAULT 'Registrar Office',
    issue_date DATE NOT NULL DEFAULT CURRENT_DATE,
    valid_until DATE,                              -- NULL means lifelong validity
    is_revoked BOOLEAN DEFAULT FALSE,
    revocation_reason TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_issued_request FOREIGN KEY (request_id) 
        REFERENCES certificate_requests(request_id) ON DELETE CASCADE
);

-- Table 6: Verification Logs (Audit trail of external employers / verifiers checking certificates)
CREATE TABLE verification_logs (
    log_id SERIAL PRIMARY KEY,
    cert_number_queried VARCHAR(50) NOT NULL,
    verifier_name VARCHAR(100) NOT NULL,
    verifier_org VARCHAR(150) NOT NULL,
    verifier_email VARCHAR(120),
    verification_result VARCHAR(20) NOT NULL CHECK (verification_result IN ('VALID', 'INVALID', 'REVOKED')),
    verified_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ip_address VARCHAR(45) DEFAULT '127.0.0.1'
);

-- ====================================================================
-- 3. TRIGGERS (AUTOMATION & INTEGRITY ENFORCEMENT)
-- ====================================================================

-- TRIGGER 1: trg_after_certificate_issued
-- Purpose: Once an official certificate is generated into 'certificates_issued',
-- automatically sync the status of 'certificate_requests' to 'ISSUED' and record updated_at.
CREATE OR REPLACE FUNCTION fn_sync_certificate_status()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE certificate_requests
    SET status = 'ISSUED',
        updated_at = CURRENT_TIMESTAMP
    WHERE request_id = NEW.request_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_after_certificate_issued
AFTER INSERT ON certificates_issued
FOR EACH ROW
EXECUTE FUNCTION fn_sync_certificate_status();


-- TRIGGER 2: trg_check_duplicate_pending
-- Purpose: Prevents a student from spamming duplicate requests for the same certificate
-- type while an existing request is still 'PENDING'.
CREATE OR REPLACE FUNCTION fn_prevent_duplicate_pending_request()
RETURNS TRIGGER AS $$
DECLARE
    pending_count INT;
BEGIN
    SELECT COUNT(*) INTO pending_count
    FROM certificate_requests
    WHERE student_id = NEW.student_id
      AND cert_type_id = NEW.cert_type_id
      AND status = 'PENDING';

    IF pending_count > 0 THEN
        RAISE EXCEPTION 'A pending request already exists for this certificate type for student ID %.', NEW.student_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_duplicate_pending
BEFORE INSERT ON certificate_requests
FOR EACH ROW
EXECUTE FUNCTION fn_prevent_duplicate_pending_request();

-- ====================================================================
-- 4. STORED PROCEDURES (TRANSACTIONAL BUSINESS LOGIC)
-- ====================================================================

-- STORED PROCEDURE 1: sp_approve_and_issue_certificate
-- Purpose: Approves a student request and formally issues a verifiable certificate.
-- Generates a unique serial number and cryptographic digital hash atomically.
CREATE OR REPLACE PROCEDURE sp_approve_and_issue_certificate(
    IN p_request_id INT,
    IN p_admin_remarks TEXT,
    IN p_officer_name VARCHAR
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_req_status VARCHAR(20);
    v_dept_code VARCHAR(10);
    v_cert_code VARCHAR(20);
    v_student_id INT;
    v_cert_number VARCHAR(40);
    v_hash VARCHAR(64);
    v_year VARCHAR(4);
BEGIN
    -- 1. Check request existence and current status
    SELECT cr.status, s.student_id, d.dept_code, ct.code
    INTO v_req_status, v_student_id, v_dept_code, v_cert_code
    FROM certificate_requests cr
    JOIN students s ON cr.student_id = s.student_id
    JOIN departments d ON s.department_id = d.department_id
    JOIN certificate_types ct ON cr.cert_type_id = ct.cert_type_id
    WHERE cr.request_id = p_request_id;

    IF v_req_status IS NULL THEN
        RAISE EXCEPTION 'Request with ID % does not exist.', p_request_id;
    END IF;

    IF v_req_status = 'ISSUED' THEN
        RAISE EXCEPTION 'Request ID % is already ISSUED.', p_request_id;
    END IF;

    IF v_req_status = 'REJECTED' THEN
        RAISE EXCEPTION 'Request ID % was already REJECTED.', p_request_id;
    END IF;

    -- 2. Generate Unique Formatted Certificate Number (e.g. EDU-2026-CS-00042)
    v_year := TO_CHAR(CURRENT_DATE, 'YYYY');
    v_cert_number := 'EDU-' || v_year || '-' || v_dept_code || '-' || LPAD(p_request_id::TEXT, 5, '0');

    -- 3. Generate Tamper-Proof Cryptographic Hash (SHA256 simulation)
    v_hash := MD5(v_cert_number || '-' || v_student_id::TEXT || '-' || CURRENT_TIMESTAMP::TEXT) || 
              MD5(RANDOM()::TEXT);

    -- 4. Update request remarks
    UPDATE certificate_requests
    SET admin_remarks = COALESCE(p_admin_remarks, 'Approved and processed by administrative registrar.'),
        updated_at = CURRENT_TIMESTAMP
    WHERE request_id = p_request_id;

    -- 5. Insert into certificates_issued
    -- (This will trigger trg_after_certificate_issued, which automatically sets status = 'ISSUED')
    INSERT INTO certificates_issued (
        request_id,
        cert_number,
        verification_hash,
        issued_by,
        issue_date
    ) VALUES (
        p_request_id,
        v_cert_number,
        v_hash,
        COALESCE(p_officer_name, 'Dean of Academic Affairs'),
        CURRENT_DATE
    );

    RAISE NOTICE 'Certificate % successfully generated for Request ID %', v_cert_number, p_request_id;
END;
$$;


-- STORED PROCEDURE 2: sp_reject_request
-- Purpose: Safely rejects a request with recorded justification.
CREATE OR REPLACE PROCEDURE sp_reject_request(
    IN p_request_id INT,
    IN p_reason TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_status VARCHAR(20);
BEGIN
    SELECT status INTO v_current_status
    FROM certificate_requests
    WHERE request_id = p_request_id;

    IF v_current_status IS NULL THEN
        RAISE EXCEPTION 'Request ID % not found.', p_request_id;
    END IF;

    IF v_current_status = 'ISSUED' THEN
        RAISE EXCEPTION 'Cannot reject an already ISSUED certificate for Request ID %.', p_request_id;
    END IF;

    UPDATE certificate_requests
    SET status = 'REJECTED',
        admin_remarks = p_reason,
        updated_at = CURRENT_TIMESTAMP
    WHERE request_id = p_request_id;

    RAISE NOTICE 'Request ID % rejected with reason: %', p_request_id, p_reason;
END;
$$;
