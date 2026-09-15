import { createClient } from '@supabase/supabase-js'
import nodemailer from 'nodemailer'

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
}

function escapeHtml(value: string) {
  return value.replace(/[&<>'"]/g, character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' })[character] || character)
}

export default async (request: Request) => {
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  const supabaseUrl = Netlify.env.get('VITE_SUPABASE_URL')
  const publishableKey = Netlify.env.get('VITE_SUPABASE_PUBLISHABLE_KEY')
  const serviceRoleKey = Netlify.env.get('SUPABASE_SERVICE_ROLE_KEY')
  const smtpUser = Netlify.env.get('ZOHO_SMTP_USER')
  const smtpPassword = Netlify.env.get('ZOHO_SMTP_PASSWORD')
  const smtpFrom = Netlify.env.get('ZOHO_SMTP_FROM') || smtpUser
  const smtpHost = Netlify.env.get('ZOHO_SMTP_HOST') || 'smtp.zoho.com'
  const siteUrl = (Netlify.env.get('URL') || 'https://thereaderroom.netlify.app').replace(/\/$/, '')

  if (!supabaseUrl || !publishableKey || !serviceRoleKey || !smtpUser || !smtpPassword || !smtpFrom) {
    return json({ error: 'Invitation email environment variables are incomplete.' }, 500)
  }

  const token = request.headers.get('authorization')?.replace(/^Bearer\s+/i, '')
  if (!token) return json({ error: 'Authentication required.' }, 401)

  const publicClient = createClient(supabaseUrl, publishableKey, { auth: { persistSession: false } })
  const adminClient = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } })
  const { data: userData, error: userError } = await publicClient.auth.getUser(token)
  if (userError || !userData.user) return json({ error: 'Your session is not valid.' }, 401)

  const { data: senderProfile } = await adminClient.from('profiles').select('role,full_name').eq('id', userData.user.id).single()
  if (!senderProfile) return json({ error: 'Sender profile not found.' }, 403)

  const body = await request.json() as { type?: 'author' | 'reader'; email?: string; book_id?: string }
  const email = body.email?.trim().toLowerCase()
  if (!email || !body.type) return json({ error: 'Invitation details are incomplete.' }, 400)

  let portalUrl = `${siteUrl}/reader-login`
  let subject = 'You are invited to The Reader Room'
  let heading = 'You have a new beta-reading invitation.'
  let detail = 'A manuscript is waiting for you in The Reader Room.'

  if (body.type === 'author') {
    if (senderProfile.role !== 'admin') return json({ error: 'Administrator access required.' }, 403)
    const { data: invitation } = await adminClient.from('author_invitations').select('id').eq('email', email).is('revoked_at', null).maybeSingle()
    if (!invitation) return json({ error: 'Active author access was not found.' }, 404)
    portalUrl = `${siteUrl}/author-login`
    subject = 'You are invited to join The Reader Room as an author'
    heading = 'You have been invited as an author.'
    detail = 'You can upload manuscripts, invite beta readers, and review private feedback.'
  } else {
    if (!body.book_id) return json({ error: 'A manuscript is required.' }, 400)
    const { data: invitation } = await adminClient.from('reader_invitations').select('id,books(title,author_id,author_name)').eq('book_id', body.book_id).eq('email', email).is('revoked_at', null).maybeSingle()
    if (!invitation?.books) return json({ error: 'Active reader access was not found.' }, 404)
    const book = Array.isArray(invitation.books) ? invitation.books[0] : invitation.books
    if (senderProfile.role !== 'admin' && book.author_id !== userData.user.id) return json({ error: 'You cannot invite readers to this manuscript.' }, 403)
    subject = `You are invited to beta read ${book.title}`
    heading = `You have been invited to beta read ${book.title}.`
    detail = `${book.author_name} has invited you to read securely and leave private feedback.`
  }

  const transporter = nodemailer.createTransport({ host: smtpHost, port: 465, secure: true, auth: { user: smtpUser, pass: smtpPassword } })
  await transporter.sendMail({
    from: `The Reader Room <${smtpFrom}>`,
    to: email,
    subject,
    text: `${heading}\n\n${detail}\n\nOpen your portal: ${portalUrl}\n\nFor your first visit, choose “First sign-in or forgot your password?” to verify your email and create a secure password.`,
    html: `<div style="font-family:Arial,sans-serif;color:#2a2030;line-height:1.6;max-width:620px;margin:auto"><h1 style="font-family:Georgia,serif;color:#542b66">${escapeHtml(heading)}</h1><p>${escapeHtml(detail)}</p><p><a href="${portalUrl}" style="display:inline-block;background:#704086;color:#fff;text-decoration:none;padding:12px 20px;border-radius:7px;font-weight:bold">Open The Reader Room</a></p><p style="font-size:13px;color:#6f6874">For your first visit, choose <strong>First sign-in or forgot your password?</strong> to verify your email and create a secure password.</p></div>`,
  })

  return json({ sent: true })
}

export const config = { path: '/api/send-invitation' }
