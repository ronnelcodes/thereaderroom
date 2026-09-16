import { createClient } from '@supabase/supabase-js'

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
}

type CreateUserBody = {
  full_name?: string
  email?: string
  role?: 'author' | 'reader'
  temp_password?: string
  book_id?: string
}

export default async (request: Request) => {
  if (request.method !== 'POST') return json({ error: 'Method not allowed.' }, 405)

  const supabaseUrl = Netlify.env.get('VITE_SUPABASE_URL')
  const publishableKey = Netlify.env.get('VITE_SUPABASE_PUBLISHABLE_KEY')
  const serviceRoleKey = Netlify.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !publishableKey || !serviceRoleKey) {
    return json({ error: 'Account creation environment variables are incomplete.' }, 500)
  }

  const token = request.headers.get('authorization')?.replace(/^Bearer\s+/i, '')
  if (!token) return json({ error: 'Authentication required.' }, 401)

  const publicClient = createClient(supabaseUrl, publishableKey, { auth: { persistSession: false } })
  const adminClient = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } })
  const { data: userData, error: userError } = await publicClient.auth.getUser(token)
  if (userError || !userData.user) return json({ error: 'Your session is not valid.' }, 401)

  const { data: administrator } = await adminClient.from('profiles').select('role').eq('id', userData.user.id).single()
  if (administrator?.role !== 'admin') return json({ error: 'Administrator access required.' }, 403)

  let body: CreateUserBody
  try {
    body = await request.json() as CreateUserBody
  } catch {
    return json({ error: 'Invalid request body.' }, 400)
  }

  const fullName = body.full_name?.trim()
  const email = body.email?.trim().toLowerCase()
  const role = body.role
  const temporaryPassword = body.temp_password || ''
  const bookId = body.book_id?.trim() || null
  if (!fullName || !email || !role) return json({ error: 'Name, email, and role are required.' }, 400)
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: 'Enter a valid email address.' }, 400)
  if (!['author', 'reader'].includes(role)) return json({ error: 'Role must be author or reader.' }, 400)
  if (temporaryPassword.length < 10 || !/[A-Z]/.test(temporaryPassword) || !/[a-z]/.test(temporaryPassword) || !/\d/.test(temporaryPassword) || !/[^A-Za-z0-9]/.test(temporaryPassword)) {
    return json({ error: 'The temporary password does not meet the security requirements.' }, 400)
  }
  if (role === 'author' && bookId) return json({ error: 'Only readers can be assigned to a book.' }, 400)

  if (bookId) {
    const { data: book } = await adminClient.from('books').select('id').eq('id', bookId).maybeSingle()
    if (!book) return json({ error: 'The selected book was not found.' }, 404)
  }

  const { data: created, error: createError } = await adminClient.auth.admin.createUser({
    email,
    password: temporaryPassword,
    email_confirm: true,
    user_metadata: { full_name: fullName },
  })
  if (createError || !created.user) {
    const duplicate = createError?.message?.toLowerCase().includes('already')
    return json({ error: duplicate ? 'An account already exists for this email address.' : createError?.message || 'The account could not be created.' }, 400)
  }

  try {
    const { error: profileError } = await adminClient.from('profiles').upsert({
      id: created.user.id,
      email,
      full_name: fullName,
      role,
      password_set: false,
    })
    if (profileError) throw profileError

    if (role === 'reader' && bookId) {
      const { error: invitationError } = await adminClient.from('reader_invitations').upsert({
        book_id: bookId,
        email,
        reader_id: created.user.id,
        status: 'accepted',
        accepted_at: new Date().toISOString(),
        revoked_at: null,
      }, { onConflict: 'book_id,email' })
      if (invitationError) throw invitationError
    }
  } catch (error) {
    await adminClient.auth.admin.deleteUser(created.user.id)
    return json({ error: error instanceof Error ? error.message : 'The account could not be completed.' }, 500)
  }

  return json({ created: true, user_id: created.user.id, role, book_assigned: Boolean(bookId) }, 201)
}

export const config = { path: '/api/admin-create-user' }
