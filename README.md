# Site Specific Safety File Generator – online version

This is the same generator, with staff logins, a shared company database, shared document numbering, and PDF-only output. It runs as a website (hosted on Vercel), and the data is kept in Supabase.

## What is in this folder

| File | What it is |
|---|---|
| `index.html`, `app.js` | The app |
| `config.js` | Your Supabase address and publishable key (you fill this in) |
| `vercel.json` | Security settings for the website (blocks other sites, scripts and framing; no caching) |
| `supabase/schema.sql` | The database: tables, access rules, numbering and activity log |
| `supabase/ai.sql` | The AI additions only, for a database that is already set up |
| `supabase/update-2026-11-19.sql` | Word download permission and download logging, for a database that is already set up |
| `supabase/update-2026-11-19b.sql` | Saved companies, contractors and team members (with signatures), for a database that is already set up |
| `supabase/functions/ai-assist/index.ts` | The server function that connects the app to the AI |
| `logo.png` | The GSRC logo |
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

## Branding

- The app uses the GSRC logo colours: navy `#1f3469` for the top bar and headings, navy-blue `#243c78` for buttons, red `#c62f2b` for the accent line and grey `#5a5a5a` for secondary text.
- **Logo:** `logo.png` is the GSRC logo with a transparent background, sized for the screen. It shows on the sign-in screen and in the top bar. To change it, replace that file in the GitHub repository with another PNG of the same name.
- To adjust a colour, change the values at the start of the last style block in `index.html` (`--navy`, `--acc` for buttons, `--red`, `--grey`).

## Downloads

- **Download this document as PDF** (on each document) opens the browser's Save as PDF window. The text stays selectable.
- **Download all as PDF (ZIP)** makes every document in the file into its own PDF and saves them in one ZIP file, named with the document numbers. These PDFs are made as page images, so their text cannot be selected or searched.
- **Word** (on each document) and **Download all as Word (ZIP)** make editable .docx files. Only administrators and the people ticked under **Word** on the Admin page see these buttons. The buttons are hidden for everyone else, but because the files are made in the browser a technically skilled user could still produce them; every download is logged.
- Every PDF, ZIP and Word download is recorded in the activity log.

## Registers and procedures

- **Registers:** every register in the file is a printable form. Machine and equipment checklists follow the TTAPL inspection forms (weekly Monday to Sunday sheets for machines, monthly registers with fault legends for ladders, hand tools and portable electrical tools, the vehicle daily report, and the fire fighting equipment checklist). Other registers are logs with the columns that register needs. Tick **Equipment on site** on the form to add the checklist for each machine or item of equipment.
- **Procedures that are not available:** the asbestos and hazardous material discovery procedure, the explosives procedure, the explosive powered tools procedure and the demolition plan are not in the generator. If the selected work needs one of them, the app shows an error listing it and leaves it out of the file. It must be developed separately before that work starts.
- All generated documents are issued as approved. The responsible people sign where indicated.

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

## AI assistant

The app can use Claude, Anthropic's AI model, through Anthropic's API. Staff given AI access get these functions:

- **Analyse scope with AI** (under the scope of work): reads the scope of work, and a scope document if one is attached, then ticks the types of work, tasks, equipment and extra appointments it thinks the job needs, with the reason for each. It also prepares up to 15 hazards specific to the job for the baseline risk assessment (marked "(AI)" on screen), and lists anything the preparer must confirm. Check the selections, then generate. After generating, the AI writes the SHE plan automatically: under the client specification's headings when a specification is loaded, otherwise under the legal SHE plan headings for the scope. Analysing and writing the plan together count as one AI use.
- **Write SHE plan with AI** (AI tools menu): writes or rewrites the SHE plan for a generated file.

Other AI functions:

- **Read specification with AI** (Client requirements section): reads the client's specification or safety file index from a PDF, Word .docx, text file or photo of a scan, and lists the requirements in the client's numbering.
- **Check against specification (AI)** (after generating): marks each requirement covered, partly covered or missing, with an action. This is advice on screen only; it is not part of the file.
- **Improve with AI** (on each document): suggests additions for that document. Staff choose which to insert. Inserted text is marked on screen until the file is issued.

Who can use it:
- **Administrators** always have the AI functions.
- **Staff** only see and can use them when an administrator ticks **AI** next to their name on the Admin page and clicks **Save**. For everyone else the AI buttons are hidden, and the server refuses AI requests from them even if someone tries to call it directly. Switching AI on or off for a person is recorded in the activity log.

How it is protected:
- The Anthropic key is kept in Supabase as a secret and is used only by the server function. It never reaches the browser.
- The function only runs these tasks; nobody can send it other instructions.
- Every request checks that the person is signed in and active, is limited: each staff member has a total allowance of 5 AI uses (an administrator can change a person's allowance on the Admin page), and administrators are limited to 40 a day (change `admin_limit` in `ai.sql`), and is recorded in the activity log with the tokens used. Administrators see AI use per person on the Admin page.
- Team names, ID numbers and the names of the appointer, preparer and contractor representative are replaced with [name] and [ID number] before anything is sent. Signatures are never sent. A PDF or photo of the client's specification is sent as it is, so do not upload documents that contain personal information.

### Setting up the AI (about 15 minutes)
1. Anthropic API account with credit and a monthly spend limit, and a key saved in Supabase as the secret `ANTHROPIC_API_KEY` (done).
2. In Supabase **SQL Editor**, run `supabase/ai.sql` then `supabase/update-2026-11-19.sql`, then `supabase/update-2026-11-19b.sql` (new installations get it from `schema.sql`). Run it **before** uploading the new app files. It is safe to run again.
3. In Supabase **Edge Functions**, choose **Deploy a new function → Via Editor**. Name it exactly `ai-assist`, replace the sample code with the whole of `supabase/functions/ai-assist/index.ts`, and click **Deploy**.
4. Optional: add a secret `ANTHROPIC_MODEL` to use a different Claude model. The default is `claude-sonnet-5-5`.
5. Upload the new `index.html` and `app.js` to GitHub. Test **Read specification with AI** with a client index.

If the AI buttons say "Invalid JWT", open the `ai-assist` function's settings in Supabase and switch off JWT verification. The function checks the sign-in itself through the database.

## Day to day

- **New revision:** open the file, change the revision number, and generate. The earlier revision stays.
- **Someone else's file:** an administrator shares it from the Admin page.
- **Changes to the app:** update the files in GitHub; Vercel republishes automatically.
- **Backups:** Supabase takes daily backups on paid plans. On the free plan, export the database regularly (see Supabase's backup guide) and keep the copies securely, as they contain personal information.

## Testing that was done

The database rules were tested on PostgreSQL 16 against the same schema: staff cannot see or delete other people's files, cannot make themselves admin, cannot lower numbers or renumber documents, cannot read the log, and switched-off users and visitors get nothing. The app was run in Chromium against that database through a stand-in for Supabase's login and data service, with the same security headers as `vercel.json`. Sign-in, generating, saving, numbering under a clash, sharing, the admin page and sign-out all worked. The AI functions were tested with a stand-in for the AI service, not with Claude itself, so try each AI button once with a real client document before relying on them. It has **not** yet been run against a real Supabase project, so do a test round with two staff accounts before real client data goes in.
