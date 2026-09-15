# The Reader Room by Vibe & Vision Collective

A Vue 3 and Supabase application for protected beta reading.

## Included

- Email and password sign-in after one-time invitation verification
- First-time password setup and password reset by verified email code
- Administrator, author, and reader roles
- Private DOCX, TXT, and PDF manuscript uploads
- One complete manuscript with automatic chapter detection, or multiple files with one chapter per file
- Comprehensive genre selection during upload and editing
- Pre-save chapter review with rename, reorder, merge, split, remove, and content editing tools
- Version-preserving book and chapter editing for authors and administrators
- Reader invitations with a 10-reader limit per book
- Confidentiality acceptance before reading
- Author and reader watermarks
- Blocked selection, common copy shortcuts, context menu, and printing
- Sentence-level inline comments
- Saved chapter progress
- Private feedback inbox with workflow statuses
- Separate administrator, author, and beta-reader portals
- Administrator control of authors and all reader invitations
- Immediate reader removal and reader-slot reuse
- Row Level Security on all application data

## Required Supabase setup

1. Open the Supabase SQL Editor.
2. Create a new query.
3. Copy the complete contents of `supabase/schema.sql` into the editor.
4. Run the query once.
5. In Authentication email templates, replace the Magic Link template with the contents of `supabase/email-otp-template.html`. It uses `{{ .Token }}` so users receive a verification code instead of a confirmation link.
6. In Authentication URL Configuration, set the Site URL to the live Netlify address and add `/admin-login`, `/author-login`, and `/reader-login` as allowed redirect destinations.

If the original schema was already installed before author invitations were added, run `supabase/add-author-invitations.sql` once.

For an existing installation, run `supabase/add-admin-portal.sql` after the earlier migrations.

Then run `supabase/add-password-authentication.sql` to require existing and newly invited accounts to create a password after email verification.

For an existing storage bucket, run `supabase/allow-pdf-uploads.sql` once to permit PDF manuscript files.

To enable book editing on an existing installation, run `supabase/add-book-editing.sql` once in the Supabase SQL Editor. The migration is idempotent, so running it again is safe. It installs the authorized `save_book_revision` function used by the Edit screen.

Every edit creates new `manuscript_versions` and `chapters` rows, then advances `books.current_version` in the same database transaction. Existing comments and reading progress are not moved or deleted; they remain attached to the original chapter IDs.

The owner email is `thereaderroom@teejayedeloach.com`. It automatically receives the administrator role.

The public sign-in chooser routes administrators to `/admin-login`, approved authors to `/author-login`, and invited beta readers to `/reader-login`. Administrators invite or remove authors from the dedicated Authors page and manage readers from the Reader directory.

In Supabase Authentication settings, set the minimum password length to 10 and require lowercase letters, uppercase letters, numbers, and symbols. The website applies the same requirements before submitting a password.

## Netlify environment variables

Add these in Netlify under Project configuration, Environment variables:

```text
VITE_SUPABASE_URL
VITE_SUPABASE_PUBLISHABLE_KEY
SUPABASE_SERVICE_ROLE_KEY
ZOHO_SMTP_USER
ZOHO_SMTP_PASSWORD
ZOHO_SMTP_FROM
```

Use the first two values from the Supabase Connect panel. Obtain `SUPABASE_SERVICE_ROLE_KEY` from Supabase Project Settings → API Keys and keep it server-only. Set `ZOHO_SMTP_USER` and `ZOHO_SMTP_FROM` to `thereaderroom@teejayedeloach.com`, and set `ZOHO_SMTP_PASSWORD` to a Zoho app password. Never place a Supabase secret key or an email password in a `VITE_` variable or commit it to GitHub.

If the Zoho account uses a regional SMTP server, also set `ZOHO_SMTP_HOST` (for example `smtp.zoho.eu`); otherwise the function defaults to `smtp.zoho.com`.

## Local development

Copy `.env.example` to `.env.local`, add the two browser-safe values, then run:

```bash
npm install
npm run dev
```

## Production build

```bash
npm run build
```

## Remaining production phase

Invitation emails are sent by the Netlify function after the server-only variables above are configured. Scheduled reminder emails are not yet implemented.

## Security boundary

Browser controls deter casual copying but cannot guarantee screenshot prevention. Personalized reader watermarks, private storage, access revocation, and Row Level Security are the primary safeguards.
