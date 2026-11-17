# Site Specific Safety File Generator – online version

This is the same generator, with staff logins, a shared company database, shared document numbering, and PDF-only output. It runs as a website (hosted on Vercel), and the data is kept in Supabase.

## What is in this folder

| File | What it is |
|---|---|
| `index.html`, `app.js` | The app |
| `config.js` | Your Supabase address and publishable key (you fill this in) |
| `vercel.json` | Security settings for the website (blocks other sites, scripts and framing; no caching) |
| `supabase/schema.sql` | The database: tables, access rules, numbering and activity log |
| `POPIA-CHECKLIST.md` | What the system does for POPIA and what you still need to do as a company |

## How access works

- **Nobody can sign up.** People get access only when an administrator invites them.
- **Staff** see only the company files they created and the files an administrator has shared with them.
- **Administrators** see all files. They can share files, change roles, switch people off, and read the activity log.
- **Document numbers** are issued by the database for each prefix, so two people can never get the same number. Staff can move a counter up but not down; only an administrator can lower one.
- **Company logo** is stored per document prefix and shared by everyone.
- **Team signatures** are saved with the company file and placed on the documents where that person signs.
- **Downloads:** documents leave the system only as PDFs, through the "Download this document as PDF" buttons or Print. Every download is logged with the person and the document. The backup and restore buttons from the laptop version have been removed. Printed PDFs carry "Printed by … on … – Confidential" in the footer where the browser supports it (Chrome and Edge do; Firefox may not).
- **Sessions** end after 30 minutes without activity, and when the browser tab is closed.
- **Activity log:** sign-ins, sign-outs, files created, saved, opened, shared or deleted, letters created, PDF downloads and user changes are recorded. Only administrators can read the log; nobody can edit it from the app.

## Passwords

- **Each person chooses their own password.** The invitation email opens the app on a "choose a password" screen. Nobody else, including the administrator, ever sees it.
- **Changing it:** the **Change password** button at the top of the app asks for the current password and the new one.
- **Forgotten:** **Forgot password** on the sign-in screen emails a reset link to that person's address.
- Passwords must be at least 10 characters. Supabase stores them hashed, not readable. Password changes are recorded in the activity log.

## Setting it up (about an hour)

### 1. Create the Supabase project
1. Sign in at supabase.com and create a new project. There is no South African region; choose **West Europe (London)** or **Central EU (Frankfurt)**. See the POPIA checklist about transfer outside South Africa.
2. Use a strong database password and keep it in your password manager.

### 2. Create the database
1. In the project, open **SQL Editor**, choose **New query**, paste the whole of `supabase/schema.sql` and click **Run**. It should finish without errors.

### 3. Lock down sign-in
1. **Authentication → Sign In / Providers:** switch **off** "Allow new users to sign up". Leave Email switched on. Set the minimum password length to at least 10.
2. **Authentication → URL Configuration:** set **Site URL** to your website address from step 5 (for example `https://safety.gsrcrisk.co.za`), and add the same address under **Redirect URLs**.
3. **Authentication → Emails / SMTP:** Supabase's built-in email sends only a few messages an hour. Connect your company mail server (SMTP) so invitations and password resets arrive reliably and come from your own address.

### 4. Fill in config.js
In the project click **Connect** (or **Settings → API Keys**). Copy the **Project URL** and the **publishable key** (starts with `sb_publishable_`) into `config.js`. Never use a secret or `service_role` key in this file.

### 5. Put the website online with Vercel
1. Create a private GitHub repository and upload everything in this folder.
2. In Vercel choose **Add New → Project**, import the repository, leave the build settings empty (it is a static site) and click **Deploy**.
3. Optional: under **Settings → Domains** add your own address, for example `safety.gsrcrisk.co.za`, and then update the Site URL in step 3.

### 6. Make yourself the administrator
1. In Supabase, **Authentication → Users → Add user → Send invitation** to your own email.
2. Open the email, click the link, choose a password in the app.
3. In **SQL Editor** run (with your email):
   `update public.profiles set role = 'admin' where email = 'you@gsrcrisk.co.za';`
4. Sign out and in again. You now see the **Admin** button.

### 7. Invite staff
For each person: **Authentication → Users → Add user → Send invitation**. They choose a password via the email link and appear in the Admin page as Staff. To remove someone, switch off **Active** in the Admin page; also delete or ban them in Supabase if they leave the company.

## Day to day

- **New revision:** open the file, change the revision number, and generate. The earlier revision stays.
- **Someone else's file:** an administrator shares it from the Admin page.
- **Changes to the app:** update the files in GitHub; Vercel republishes automatically.
- **Backups:** Supabase takes daily backups on paid plans. On the free plan, export the database regularly (see Supabase's backup guide) and keep the copies securely, as they contain personal information.

## Testing that was done

The database rules were tested on PostgreSQL 16 against the same schema: staff cannot see or delete other people's files, cannot make themselves admin, cannot lower numbers or renumber documents, cannot read the log, and switched-off users and visitors get nothing. The app was run in Chromium against that database through a stand-in for Supabase's login and data service, with the same security headers as `vercel.json`. Sign-in, generating, saving, numbering under a clash, sharing, the admin page and sign-out all worked. It has **not** yet been run against a real Supabase project, so do a test round with two staff accounts before real client data goes in.
