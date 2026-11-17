# POPIA checklist – Site Specific Safety File Generator (online)

This is a practical checklist, not legal advice. Have your Information Officer confirm it.

## Personal information in the system
- Names, identity numbers and roles of team members and appointees.
- Signature images of team members, where uploaded. Upload a signature only with that person's agreement, because it is placed on documents in their name.
- Contractor company details and the name of the contractor's representative.
- The names of people who appoint, prepare and approve documents.
- Staff logins: email addresses and names, plus the activity log of what each person did.
- Do **not** put special personal information (health, medical fitness results, criminal records) into the app. Medical certificates stay in the physical or controlled safety file; the app only lists them as evidence to be supplied.

## What the system does (POPIA conditions)

| POPIA | How the system meets it |
|---|---|
| Purpose specification and minimality (s10, s13) | Used only to prepare health and safety documents. ID numbers appear only on appointment letters. The form tells users to capture only people working on or appointed for the job. |
| Security safeguards (s19) | Invite-only logins; no public sign-up. Every database table has row level security: staff see only their own and shared files. Sessions end after 30 minutes idle and when the tab closes. HTTPS only, with strict browser security headers (`vercel.json`). Data is encrypted at rest by Supabase. No third-party scripts or fonts. |
| Access control and accountability (s8, s19) | Two roles (Administrator, Staff). The activity log records sign-ins, file access, saves, shares, deletions, letter creation and every PDF download. Only administrators can read it, and the app cannot change it. |
| Controlled output | Documents leave only as PDFs, and each download is logged. There are no data export or backup buttons for staff. |
| Retention (s14) | Administrators and file owners can delete company files permanently. You decide the retention period (see below). |
| Operators (s20, s21) | Supabase (database and login) and Vercel (website hosting) act as operators. |
| Cross-border transfer (s72) | Supabase has no South African region, so data will be stored in the EU or UK, where GDPR or UK GDPR applies. |
| Security compromises (s22) | The activity log helps establish what was accessed and by whom. |

## What GSRC must still do

1. **Information Officer.** Make sure your Information Officer is registered with the Information Regulator, and that this system is in your POPIA register or PAIA manual.
2. **Operator agreements (s21).** Accept Supabase's and Vercel's Data Processing Addendums (DPAs) in their dashboards or on their legal pages, and keep copies on file.
3. **Transfer outside South Africa (s72).** Record that the data is held in the EU or UK and that you rely on GDPR-level protection and the DPAs. Mention it in your privacy notice.
4. **Tell the people concerned (s18).** Tell your clients and their employees that their names and ID numbers are processed to prepare appointment letters and safety files. A clause in your service agreement, plus a line on the appointment letter, is the usual route.
5. **Retention period (s14).** Decide how long company files are kept. Safety files are often kept for the project duration plus a set number of years. Have an administrator delete expired files, and note the decision in your retention schedule.
6. **Staff rules.** Each user has their own login and must not share passwords. PDFs saved to laptops or email are personal information too: keep them in your controlled document system and delete local copies. Switch off users the day they leave.
7. **Breach procedure (s22).** If you suspect a compromise, an administrator switches off the affected accounts, changes the keys in Supabase, reviews the activity log, and the Information Officer notifies the Regulator and the people affected as soon as reasonably possible.
8. **Backups.** Use a paid Supabase plan for daily backups, or export regularly. Store copies encrypted and with restricted access.
9. **Access requests (s23, s24).** If someone asks what information you hold about them or asks for a correction, search the company files for their name and correct or delete as required.

## Optional improvements
- Two-factor sign-in (Supabase supports authenticator apps; the app would need a small addition).
- Encrypting ID numbers inside the database with a separate key.
- An automatic retention reminder for administrators.
