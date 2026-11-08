-- ====================================================================
-- SEED DATA: Realistic Academic Records for Testing & Viva Demo
-- ====================================================================

-- 1. Insert Departments
INSERT INTO departments (dept_code, dept_name, head_of_dept, contact_email) VALUES
('CSE', 'Computer Science & Engineering', 'Dr. Ramesh Sharma', 'cse.hod@university.edu'),
('ECE', 'Electronics & Communication', 'Dr. Ananya Sen', 'ece.hod@university.edu'),
('MECH', 'Mechanical Engineering', 'Dr. Suresh Patil', 'mech.hod@university.edu'),
('CIVIL', 'Civil & Environmental Engineering', 'Dr. Kavita Nair', 'civil.hod@university.edu'),
('MBA', 'Management Studies', 'Dr. Arvind Mehra', 'mba.hod@university.edu')
ON CONFLICT (dept_code) DO NOTHING;

-- 2. Insert Certificate Types
INSERT INTO certificate_types (code, title, description, processing_fee, sla_days) VALUES
('DEGREE', 'Degree Graduation Certificate', 'Official certificate of degree completion with university seal', 500.00, 7),
('PROVISIONAL', 'Provisional Degree Certificate', 'Interim certificate until the convocation ceremony', 250.00, 3),
('BONAFIDE', 'Bonafide Student Certificate', 'Certificate confirming active student enrollment and conduct', 50.00, 1),
('TRANSCRIPT', 'Official Academic Transcript', 'Complete verified grade sheet across all completed semesters', 350.00, 5),
('MIGRATION', 'Migration & Transfer Certificate', 'Required for admission into other institutions/universities', 200.00, 3),
('CONDUCT', 'Character and Conduct Certificate', 'Official document certifying student disciplinary record', 100.00, 2)
ON CONFLICT (code) DO NOTHING;

-- 3. Insert Students
INSERT INTO students (reg_number, full_name, email, phone, department_id, admission_year, graduation_year, academic_status) VALUES
('1MS21CS042', 'Aarav Patel', 'aarav.patel@student.edu', '+91 9876543210', 1, 2021, 2025, 'ACTIVE'),
('1MS21CS089', 'Sneha Kulkarni', 'sneha.k@student.edu', '+91 9876543211', 1, 2021, 2025, 'ACTIVE'),
('1MS20EC015', 'Rohan Gupta', 'rohan.gupta@student.edu', '+91 9876543212', 2, 2020, 2024, 'GRADUATED'),
('1MS20ME033', 'Pooja Iyer', 'pooja.iyer@student.edu', '+91 9876543213', 3, 2020, 2024, 'ALUMNI'),
('1MS22CV008', 'Vikram Singh', 'vikram.s@student.edu', '+91 9876543214', 4, 2022, 2026, 'ACTIVE'),
('1MS23MB012', 'Priya Deshmukh', 'priya.d@student.edu', '+91 9876543215', 5, 2023, 2025, 'ACTIVE')
ON CONFLICT (reg_number) DO NOTHING;

-- 4. Insert Initial Certificate Requests
INSERT INTO certificate_requests (student_id, cert_type_id, purpose, status, admin_remarks) VALUES
(1, 3, 'Required for State Bank Education Loan Verification', 'PENDING', NULL),
(2, 4, 'Applying for Master of Science program at Technical University of Munich', 'PENDING', NULL),
(3, 1, 'Joining Infosys as System Engineer; background check requirement', 'PENDING', NULL),
(4, 5, 'Transferring to postgraduate program in IIT Bombay', 'PENDING', NULL),
(5, 3, 'Submitting for State Govt Scholarship Scheme', 'PENDING', NULL);

-- 5. Issue One Certificate directly via the Stored Procedure to demonstrate working procedures & triggers!
CALL sp_approve_and_issue_certificate(3, 'Verified all 8 semesters grade credits cleared.', 'Registrar Dr. K. Rao');

-- 6. Insert a sample verification log to demonstrate third-party audit trail
INSERT INTO verification_logs (cert_number_queried, verifier_name, verifier_org, verifier_email, verification_result, ip_address) VALUES
('EDU-2026-ECE-00003', 'Rajesh Menon', 'Infosys BGV Team', 'bgv.verifications@infosys.com', 'VALID', '192.168.1.100');
