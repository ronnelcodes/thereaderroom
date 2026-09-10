# The Reader Room by Vibe & Vision Collective

A Vue 3 application for protected beta reading, manuscript feedback, reader progress, and author workflow management.

## Current first version

- Responsive author dashboard
- Book, reader, and feedback management views
- DOCX/manual manuscript project flow
- Reader invitations designed around email verification
- Protected reader preview with author and reader watermarks
- Disabled selection, context menu, printing, and common copy shortcuts
- Sentence-level inline feedback without ordinary text selection
- Feedback triage states and export entry point
- Author-controlled reminder and protection settings

The interface currently uses representative project data. Production authentication, manuscript storage, PDF/CSV generation, and outbound email delivery require a connected backend and email provider before public reader access.

## Development

```bash
npm install
npm run dev
```

## Production build

```bash
npm run build
```

The production output is written to `dist/`.

## Security boundary

Browser controls deter casual copying but cannot guarantee screenshot prevention. Personalized reader watermarks, short-lived sessions, access logs, and revocation should remain the primary leak deterrents in production.
