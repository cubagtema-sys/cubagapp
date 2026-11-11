-- SEC-20 follow-up: find members wrongly unlocked BEFORE commit 527066d.
--
-- READ-ONLY. Nothing here changes data. Run it in the Supabase SQL editor
-- (or psql) and have the Secretariat review every row before correcting
-- anything by hand: a member may have paid registration at the counter or by
-- bank transfer with a description these patterns don't recognise.
--
-- Background: until 527066d, every completed payment that was not a renewal or
-- package (including "Other / Miscellaneous", ID card, SIC bond, courses) set
-- members.registration_fee_paid = TRUE and gave the member a licence number.
-- And a course payment whose description matched no course enrolled the member
-- in whichever active course had the lowest id.


-- 1. Members marked "registration paid" with no paid registration/package
--    payment on record. The patterns match config/payment_validation.py
--    payment_kind().
SELECT
    m.id,
    m.name,
    m.email,
    m.status,
    m.license_number,
    m.registration_fee_paid,
    m.package_fee_paid,
    (SELECT string_agg(p.description || ' (GHS ' || p.amount || ', ' || to_char(p.paid_at, 'YYYY-MM-DD') || ')', '; ' ORDER BY p.id)
       FROM payments p
      WHERE p.member_id = m.id
        AND LOWER(p.status) IN ('paid', 'completed', 'success', 'successful')) AS paid_payments
FROM members m
WHERE COALESCE(m.role, 'member') = 'member'
  AND COALESCE(m.status, '') <> 'deleted'
  AND (m.registration_fee_paid IS TRUE OR m.application_fee_paid IS TRUE)
  AND NOT EXISTS (
      SELECT 1 FROM payments p
      WHERE p.member_id = m.id
        AND LOWER(p.status) IN ('paid', 'completed', 'success', 'successful')
        AND (
              p.fee_key IN ('registration', 'package')
           OR LOWER(p.description) LIKE '%registration%'
           OR LOWER(p.description) LIKE '%reg form%'
           OR LOWER(p.description) LIKE '%application%'
           OR LOWER(p.description) LIKE '%new member%'
           OR LOWER(p.description) LIKE '%entrance%'
           OR LOWER(p.description) LIKE '%package%'
           OR LOWER(p.description) LIKE '%membership dues%'
           OR LOWER(p.description) LIKE '%clearing & forwarding only%'
           OR LOWER(p.description) LIKE '%consolidation only%'
           OR LOWER(p.description) LIKE '%licentiate membership%'
           OR LOWER(p.description) LIKE '%associate membership%'
        )
  )
ORDER BY m.id;


-- 2. Course enrolments whose payment doesn't name that course (possible
--    "first course" mis-enrolments). Free enrolments with no payment are
--    excluded.
SELECT
    e.member_id,
    mem.name AS member_name,
    e.course_id,
    c.title AS enrolled_course,
    p.id AS payment_id,
    p.description AS payment_description,
    p.amount,
    e.payment_confirmed_at
FROM cti_course_enrollments e
JOIN cti_courses c ON c.id = e.course_id
JOIN members mem ON mem.id = e.member_id
JOIN payments p ON p.payment_ref = e.payment_ref AND p.member_id = e.member_id
WHERE POSITION(LOWER(c.title) IN LOWER(COALESCE(p.description, ''))) = 0
  AND COALESCE(p.fee_key, '') <> 'course:' || e.course_id
ORDER BY e.payment_confirmed_at DESC NULLS LAST;


-- 3. (Optional) Correcting a confirmed case, ONE member at a time, after review:
--
--   BEGIN;
--   UPDATE members
--      SET registration_fee_paid = FALSE, application_fee_paid = FALSE
--    WHERE id = <member id> AND package_fee_paid IS NOT TRUE;
--   -- check the row, then COMMIT; (or ROLLBACK;)
--
-- Leave license_number alone unless the Secretariat says otherwise: it may
-- already be printed on documents.
