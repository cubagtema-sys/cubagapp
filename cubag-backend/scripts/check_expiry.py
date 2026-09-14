import os
import sys
from datetime import datetime, date, timedelta

# Add parent directory to path to import config and utils
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config.db import get_db

def run_graduated_expiry_check():
    """
    Graduated 90-Day License Expiration & Automated Reminder Job.
    Checks all members' license expiration dates and triggers tiered reminders:
      - Phase 1 (> 90 Days): Active standing, no alert needed.
      - Phase 2 (61-90 Days): 90-Day Notice (1st Quarter Warning).
      - Phase 3 (31-60 Days): 60-Day Notice (Formal Reminder).
      - Phase 4 (0-30 Days): 30-Day Notice (Urgent Countdown).
      - Expired (< 0 Days): License Expired / Immediate Action Required.
    """
    conn = get_db()
    today = date.today()
    
    try:
        with conn.cursor() as cursor:
            cursor.execute("""
                SELECT id, name, email, company, status, license_number, license_expiry_date
                FROM members
                WHERE license_expiry_date IS NOT NULL
                ORDER BY license_expiry_date ASC
            """)
            members = cursor.fetchall()
            
            print("=" * 80)
            print("CUBAG GRADUATED 90-DAY LICENSE EXPIRATION AUDIT & REMINDER JOB")
            print(f"Date: {today.strftime('%d %b %Y')}")
            print("=" * 80)
            print(f"{'ID':<6} {'Name':<22} {'Status':<10} {'Expiry Date':<14} {'Days Left':<12} {'Tier / Action'}")
            print("-" * 80)
            
            alerts_triggered = 0
            for m in members:
                exp_raw = m['license_expiry_date']
                exp_date = None
                if isinstance(exp_raw, str):
                    try:
                        exp_date = datetime.strptime(exp_raw, '%Y-%m-%d').date()
                    except Exception:
                        pass
                elif isinstance(exp_raw, date):
                    exp_date = exp_raw
                    
                if not exp_date:
                    continue
                    
                days_left = (exp_date - today).days
                member_id = m['id']
                member_name = m['name'] or 'Unknown'
                status = str(m['status'] or '').upper()
                
                # Determine Graduated Tier
                tier_label = ""
                task_title = ""
                task_desc = ""
                
                if days_left < 0:
                    tier_label = f"🔴 EXPIRED ({abs(days_left)}d ago)"
                    task_title = "🔴 IMMEDIATE ACTION: License Expired - Renew Now"
                    task_desc = f"Your annual membership license expired on {exp_date.strftime('%d %b %Y')}. Please complete your renewal payment immediately to restore Active Standing."
                elif days_left <= 30:
                    tier_label = "🔴 URGENT (<= 30 Days)"
                    task_title = f"🔴 Urgent Renewal: License Expires in {days_left} Days"
                    task_desc = f"Your annual license expires on {exp_date.strftime('%d %b %Y')}. Renew immediately to avoid suspension of your compliance standing."
                elif days_left <= 60:
                    tier_label = "🟠 FORMAL (<= 60 Days)"
                    task_title = f"🟠 Formal Notice: License Expires in {days_left} Days"
                    task_desc = f"You have approx. 2 months remaining until your license expires on {exp_date.strftime('%d %b %Y')}. The renewal window is open."
                elif days_left <= 90:
                    tier_label = "🟡 90-DAY WINDOW OPEN"
                    task_title = f"🟡 90-Day Notice: Annual License Renewal Window Open"
                    task_desc = f"Your annual membership license will expire in 3 months ({exp_date.strftime('%d %b %Y')}). You can now begin submitting renewal documents and dues."
                else:
                    months_approx = round(days_left / 30)
                    tier_label = f"🟢 ACTIVE (~{months_approx}m left)"
                    
                print(f"{member_id:<6} {member_name[:20]:<22} {status:<10} {exp_date.strftime('%Y-%m-%d'):<14} {days_left:<12} {tier_label}")
                
                # Trigger task for members in the 90-day window or expired
                if days_left <= 90 and task_title:
                    # Check if a similar renewal task was already created in the last 14 days to prevent duplicate spam
                    cursor.execute("""
                        SELECT id FROM tasks 
                        WHERE member_id = %s 
                          AND title ILIKE '%%%s%%' 
                          AND created_at >= NOW() - INTERVAL '14 days'
                    """, (member_id, "License"))
                    existing_task = cursor.fetchone()
                    
                    if not existing_task:
                        due_date = exp_date.strftime('%Y-%m-%d')
                        cursor.execute("""
                            INSERT INTO tasks (member_id, title, description, due_date)
                            VALUES (%s, %s, %s, %s)
                        """, (member_id, task_title, task_desc, due_date))
                        alerts_triggered += 1
                        
            conn.commit()
            print("-" * 80)
            print(f"Audit completed successfully. Automated reminder tasks triggered: {alerts_triggered}")
            print("=" * 80)
            
    except Exception as e:
        conn.rollback()
        print(f"[Error running expiry check] {e}")
    finally:
        conn.close()

if __name__ == "__main__":
    run_graduated_expiry_check()
