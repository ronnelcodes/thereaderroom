# The Reader Room by Vibe & Vision Collective

A Vue 3 and Supabase application for protected beta reading.

## Included

- Passwordless email-code sign-in
- Administrator, author, and reader roles
- Private DOCX and TXT manuscript uploads
- Automatic chapter detection
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
5. In Authentication email templates, configure the Magic Link template to display `{{ .Token }}` so users receive a verification code.

If the original schema was already installed before author invitations were added, run `supabase/add-author-invitations.sql` once.

For an existing installation, run `supabase/add-admin-portal.sql` after the earlier migrations.

The owner email is `thereaderroom@teejayedeloach.com`. It automatically receives the administrator role.

The public sign-in chooser routes administrators to `/admin-login`, approved authors to `/author-login`, and invited beta readers to `/reader-login`. Administrators invite or remove authors from Workspace Settings and manage readers from the Reader directory.

## Netlify environment variables

Add these in Netlify under Project configuration, Environment variables:

```text
VITE_SUPABASE_URL
VITE_SUPABASE_PUBLISHABLE_KEY
```

Use the values from the Supabase Connect panel. Never place a Supabase secret key or database password in a `VITE_` variable.

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

Invitation and reminder emails require a server-side email provider and scheduled function. Reader access already works by creating an invitation in the author dashboard and having the reader sign in with that exact email address.

## Security boundary

Browser controls deter casual copying but cannot guarantee screenshot prevention. Personalized reader watermarks, private storage, access revocation, and Row Level Security are the primary safeguards.
