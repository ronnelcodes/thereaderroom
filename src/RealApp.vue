<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { Bell, BookOpen, Check, ChevronLeft, ChevronRight, FileText, Gauge, Inbox, LayoutDashboard, LockKeyhole, LogOut, Menu, MessageSquare, MoreHorizontal, Plus, Send, Settings, ShieldCheck, Sparkles, Upload, Users, X } from 'lucide-vue-next'
import { isSupabaseConfigured, supabase } from './lib/supabase'

const OWNER_EMAIL = 'teejayedeloachwrites@gmail.com'
const loading = ref(true), actionLoading = ref(false)
const session = ref(null), profile = ref(null)
const authEmail = ref(''), authCode = ref(''), codeSent = ref(false), authError = ref(''), errorMessage = ref('')
const activeView = ref('dashboard'), mobileNav = ref(false), toast = ref('')
const books = ref([]), invitations = ref([]), feedback = ref([]), chapters = ref([])
const selectedBook = ref(null), selectedChapter = ref(null)
const showNewBook = ref(false), showInvite = ref(false), showReader = ref(false), showAgreement = ref(false), showComment = ref(false), showNotice = ref(false)
const selectedSentence = ref(''), selectedSentenceIndex = ref(null), commentText = ref('')
const newBook = ref({ title:'', author_name:'Teejaye Deloach', genre:'', deadline:'', manuscriptText:'', file:null })
const newInvite = ref({ email:'', book_id:'', deadline:'' })
let authSubscription

const nav = [
  {id:'dashboard',label:'Overview',icon:LayoutDashboard},{id:'books',label:'Books',icon:BookOpen},
  {id:'readers',label:'Readers',icon:Users},{id:'feedback',label:'Feedback',icon:MessageSquare},{id:'settings',label:'Settings',icon:Settings}
]
const isAuthor = computed(()=>['admin','author'].includes(profile.value?.role))
const pageTitle = computed(()=>nav.find(i=>i.id===activeView.value)?.label||'Overview')
const activeBooks = computed(()=>books.value.filter(b=>b.status==='active'))
const activeReaders = computed(()=>invitations.value.filter(i=>!i.revoked_at&&i.status!=='revoked'))
const newFeedback = computed(()=>feedback.value.filter(i=>i.status==='new'))
const readerInvitations = computed(()=>invitations.value.filter(i=>i.reader_id===session.value?.user?.id||i.email?.toLowerCase()===session.value?.user?.email?.toLowerCase()))
const readerEmail = computed(()=>session.value?.user?.email||'')
const chapterSentences = computed(()=> (selectedChapter.value?.content||'').split(/(?<=[.!?])\s+(?=[A-Z“"'])/).filter(Boolean))

function flash(message){toast.value=message;setTimeout(()=>toast.value='',2800)}
function changeView(id){activeView.value=id;mobileNav.value=false}

async function sendCode(){
  authError.value=''; if(!authEmail.value.trim())return
  actionLoading.value=true
  const {error}=await supabase.auth.signInWithOtp({email:authEmail.value.trim().toLowerCase(),options:{shouldCreateUser:true,data:{full_name:authEmail.value.split('@')[0]}}})
  actionLoading.value=false; if(error)authError.value=error.message;else codeSent.value=true
}
async function verifyCode(){
  authError.value='';actionLoading.value=true
  const {error}=await supabase.auth.verifyOtp({email:authEmail.value.trim().toLowerCase(),token:authCode.value.trim(),type:'email'})
  actionLoading.value=false;if(error)authError.value=error.message
}
async function signOut(){await supabase.auth.signOut();profile.value=null;books.value=[];invitations.value=[];feedback.value=[]}

async function loadWorkspace(){
  if(!session.value)return;loading.value=true;errorMessage.value=''
  try{
    const {data:p,error:pe}=await supabase.from('profiles').select('*').eq('id',session.value.user.id).single();if(pe)throw pe;profile.value=p
    if(['admin','author'].includes(p.role))await loadAuthorData();else await loadReaderData()
  }catch(error){errorMessage.value=error.message||'The workspace could not be loaded.'}finally{loading.value=false}
}
async function loadAuthorData(){
  const {data:b,error}=await supabase.from('books').select('*').order('updated_at',{ascending:false});if(error)throw error;books.value=b||[]
  const ids=books.value.map(x=>x.id);if(!ids.length){invitations.value=[];feedback.value=[];return}
  const [ir,fr]=await Promise.all([
    supabase.from('reader_invitations').select('*').in('book_id',ids).order('invited_at',{ascending:false}),
    supabase.from('comments').select('*,chapters(title,chapter_number),books(title),profiles!comments_reader_id_fkey(full_name,email)').in('book_id',ids).order('created_at',{ascending:false})
  ]);if(ir.error)throw ir.error;if(fr.error)throw fr.error;invitations.value=ir.data||[];feedback.value=fr.data||[]
}
async function loadReaderData(){
  const {data,error}=await supabase.from('reader_invitations').select('*,books(*)').order('invited_at',{ascending:false});if(error)throw error
  invitations.value=data||[];books.value=invitations.value.map(i=>i.books).filter(Boolean)
}

function handleFile(e){newBook.value.file=e.target.files?.[0]||null;if(newBook.value.file&&!newBook.value.title)newBook.value.title=newBook.value.file.name.replace(/\.(docx|txt)$/i,'')}
async function extractText(file){if(!file)return newBook.value.manuscriptText.trim();if(file.name.toLowerCase().endsWith('.txt'))return file.text();const mammoth=await import('mammoth/mammoth.browser');const arrayBuffer=await file.arrayBuffer();return (await mammoth.extractRawText({arrayBuffer})).value.trim()}
function splitChapters(text){
  const clean=text.replace(/\r\n/g,'\n').trim();const pattern=/^(chapter\s+(?:\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty)[^\n]*)$/gim;const matches=[...clean.matchAll(pattern)]
  if(!matches.length)return[{chapter_number:1,title:'Chapter 1',content:clean}]
  return matches.map((m,i)=>({chapter_number:i+1,title:m[0].trim(),content:clean.slice(m.index+m[0].length,matches[i+1]?.index??clean.length).trim()})).filter(c=>c.content)
}
async function createBook(){
  if(!newBook.value.title.trim()||(!newBook.value.file&&!newBook.value.manuscriptText.trim()))return flash('Add a title and manuscript file or text.')
  actionLoading.value=true
  try{
    const text=await extractText(newBook.value.file)
    const {data:book,error}=await supabase.from('books').insert({author_id:session.value.user.id,title:newBook.value.title.trim(),author_name:newBook.value.author_name.trim()||profile.value.full_name||'Author',genre:newBook.value.genre.trim()||null,overall_deadline:newBook.value.deadline||null,status:'active'}).select().single();if(error)throw error
    let path=null
    if(newBook.value.file){path=`${session.value.user.id}/${book.id}/v1-${Date.now()}-${newBook.value.file.name.replace(/[^a-zA-Z0-9._-]/g,'-')}`;const up=await supabase.storage.from('manuscripts').upload(path,newBook.value.file);if(up.error)throw up.error;await supabase.from('books').update({manuscript_path:path,manuscript_filename:newBook.value.file.name}).eq('id',book.id)}
    await supabase.from('manuscript_versions').insert({book_id:book.id,version_number:1,storage_path:path,filename:newBook.value.file?.name||null,created_by:session.value.user.id})
    const rows=splitChapters(text).map(c=>({...c,book_id:book.id,version_number:1}));const cr=await supabase.from('chapters').insert(rows);if(cr.error)throw cr.error
    await supabase.from('reminder_settings').insert({book_id:book.id})
    newBook.value={title:'',author_name:profile.value.full_name||'Teejaye Deloach',genre:'',deadline:'',manuscriptText:'',file:null};showNewBook.value=false;await loadAuthorData();flash(`${book.title} is ready for readers.`)
  }catch(error){flash(error.message||'The book could not be created.')}finally{actionLoading.value=false}
}

function startInvite(bookId=''){newInvite.value={email:'',book_id:bookId||books.value[0]?.id||'',deadline:''};showInvite.value=true}
async function inviteReader(){
  if(!newInvite.value.email||!newInvite.value.book_id)return;actionLoading.value=true
  const {error}=await supabase.from('reader_invitations').insert({book_id:newInvite.value.book_id,email:newInvite.value.email.trim().toLowerCase(),individual_deadline:newInvite.value.deadline||null});actionLoading.value=false
  if(error)flash(error.message);else{showInvite.value=false;await loadAuthorData();flash('Reader access created. Email automation is the next setup phase.')}
}
async function revokeInvitation(i){const {error}=await supabase.from('reader_invitations').update({status:'revoked',revoked_at:new Date().toISOString()}).eq('id',i.id);if(error)flash(error.message);else{await loadAuthorData();flash('Reader access revoked.')}}

async function openBook(book,invitation=null){
  selectedBook.value=book;const {data,error}=await supabase.from('chapters').select('*').eq('book_id',book.id).eq('version_number',book.current_version||1).order('chapter_number');if(error)return flash(error.message)
  chapters.value=data||[];selectedChapter.value=chapters.value[0]||null
  if(!isAuthor.value&&invitation){selectedBook.value._invitation=invitation;const {data:a}=await supabase.from('reader_agreements').select('id').eq('invitation_id',invitation.id).maybeSingle();if(!a){showAgreement.value=true;return}}
  showReader.value=true
}
async function acceptAgreement(){
  const i=selectedBook.value?._invitation;if(!i)return
  const {error}=await supabase.from('reader_agreements').insert({invitation_id:i.id,reader_id:session.value.user.id});if(error)return flash(error.message)
  showAgreement.value=false;showReader.value=true
}
function openSentence(sentence,index){if(isAuthor.value)return;selectedSentence.value=sentence;selectedSentenceIndex.value=index;commentText.value='';showComment.value=true}
async function submitComment(){
  if(!commentText.value.trim())return;actionLoading.value=true
  const {error}=await supabase.from('comments').insert({book_id:selectedBook.value.id,chapter_id:selectedChapter.value.id,reader_id:session.value.user.id,sentence_index:selectedSentenceIndex.value,quoted_text:selectedSentence.value,comment_text:commentText.value.trim()});actionLoading.value=false
  if(error)flash(error.message);else{showComment.value=false;flash('Comment saved.')}
}
async function completeChapter(){
  const i=selectedBook.value._invitation;const {error}=await supabase.from('reading_progress').upsert({invitation_id:i.id,chapter_id:selectedChapter.value.id,reader_id:session.value.user.id,percent:100,completed:true,completed_at:new Date().toISOString(),last_opened_at:new Date().toISOString()},{onConflict:'invitation_id,chapter_id,reader_id'});if(error)flash(error.message);else flash('Chapter marked complete.')
}
async function updateStatus(item,status){const {error}=await supabase.from('comments').update({status}).eq('id',item.id);if(error)flash(error.message);else{item.status=status;flash(`Feedback marked ${status}.`)}}

function blockAction(e){if(!showReader.value)return;const k=e.key.toLowerCase();if(((e.ctrlKey||e.metaKey)&&['c','x','a','p','s','u'].includes(k))||e.key==='PrintScreen'){e.preventDefault();showNotice.value=true;setTimeout(()=>showNotice.value=false,1800)}}
function blockContext(e){if(showReader.value){e.preventDefault();showNotice.value=true;setTimeout(()=>showNotice.value=false,1800)}}

onMounted(async()=>{
  window.addEventListener('keydown',blockAction);window.addEventListener('contextmenu',blockContext)
  if(!isSupabaseConfigured){loading.value=false;return}
  const {data}=await supabase.auth.getSession();session.value=data.session;if(session.value)await loadWorkspace();else loading.value=false
  authSubscription=supabase.auth.onAuthStateChange(async(_,s)=>{session.value=s;if(s)await loadWorkspace()}).data.subscription
})
onBeforeUnmount(()=>{window.removeEventListener('keydown',blockAction);window.removeEventListener('contextmenu',blockContext);authSubscription?.unsubscribe()})
</script>

<template>
  <div v-if="loading" class="center-screen"><div class="loader"></div><strong>Opening The Reader Room…</strong></div>
  <div v-else-if="!isSupabaseConfigured" class="center-screen error-screen"><ShieldCheck :size="34"/><h1>Connection needed</h1><p>Add the Supabase project URL and publishable key to the Netlify environment.</p></div>

  <main v-else-if="!session" class="auth-page">
    <section class="auth-brand"><div class="brand-mark large">V<span>&</span>V</div><p class="eyebrow">VIBE & VISION COLLECTIVE</p><h1>The Reader Room</h1><p>A protected place for meaningful stories, trusted readers, and feedback that helps the work grow.</p><div class="auth-promise"><ShieldCheck/><span>Private manuscripts<small>Personalized access and accountable feedback</small></span></div></section>
    <section class="auth-card"><div v-if="!codeSent"><p class="eyebrow">WELCOME</p><h2>Enter the room.</h2><p>We’ll email you a one-time verification code. No password required.</p><label>Email address<input v-model="authEmail" type="email" autocomplete="email" placeholder="you@example.com" @keyup.enter="sendCode"/></label><button class="primary full" :disabled="actionLoading" @click="sendCode">{{actionLoading?'Sending…':'Email my code'}} <ChevronRight :size="17"/></button></div><div v-else><button class="text-button auth-back" @click="codeSent=false;authCode=''">← Change email</button><p class="eyebrow">CHECK YOUR EMAIL</p><h2>Enter your code.</h2><p>We sent a code to <strong>{{authEmail}}</strong>.</p><label>Verification code<input v-model="authCode" class="code-input" inputmode="numeric" maxlength="8" placeholder="000000" @keyup.enter="verifyCode"/></label><button class="primary full" :disabled="actionLoading" @click="verifyCode">{{actionLoading?'Verifying…':'Enter The Reader Room'}}</button></div><p v-if="authError" class="form-error">{{authError}}</p><small class="auth-terms">By continuing, you agree to respect manuscript confidentiality and the creative work shared here.</small></section>
  </main>

  <div v-else-if="errorMessage" class="center-screen error-screen"><ShieldCheck :size="34"/><h1>Setup is not finished</h1><p>{{errorMessage}}</p><p>Run the Reader Room database setup in Supabase, then try again.</p><button class="primary" @click="loadWorkspace">Try again</button></div>

  <div v-else-if="!isAuthor" class="reader-home">
    <header class="reader-home-header"><div class="brand"><div class="brand-mark">V<span>&</span>V</div><div><strong>THE READER ROOM</strong><small>Vibe & Vision Collective</small></div></div><div><span>{{readerEmail}}</span><button class="secondary" @click="signOut"><LogOut :size="16"/> Sign out</button></div></header>
    <main class="reader-library"><p class="eyebrow">YOUR READING SHELF</p><h1>Welcome to The Reader Room.</h1><p>Your invited manuscripts appear here. Feedback from other readers is never shown to you.</p><section v-if="readerInvitations.length" class="reader-book-grid"><article v-for="invite in readerInvitations" :key="invite.id" class="reader-book"><div class="book-cover large holiday"><BookOpen/></div><div><span class="status" :class="invite.status">{{invite.status}}</span><h2>{{invite.books?.title}}</h2><p>{{invite.books?.author_name}}</p><small>Deadline: {{invite.individual_deadline||invite.books?.overall_deadline||'Set by author'}}</small><button class="primary" :disabled="invite.status==='revoked'" @click="openBook(invite.books,invite)">Continue reading <ChevronRight :size="16"/></button></div></article></section><section v-else class="panel empty-state"><Inbox :size="34"/><h2>No invitations yet</h2><p>Sign in with the exact email address the author invited.</p></section></main>
  </div>

  <div v-else class="app-shell">
    <aside class="sidebar" :class="{open:mobileNav}"><button class="mobile-close" @click="mobileNav=false"><X/></button><div class="brand"><div class="brand-mark">V<span>&</span>V</div><div><strong>THE READER ROOM</strong><small>Vibe & Vision Collective</small></div></div><nav><button v-for="item in nav" :key="item.id" :class="{active:activeView===item.id}" @click="changeView(item.id)"><component :is="item.icon" :size="19"/><span>{{item.label}}</span><span v-if="item.id==='feedback'&&newFeedback.length" class="nav-count">{{newFeedback.length}}</span></button></nav><div class="collective-card"><Sparkles :size="18"/><strong>Creative community</strong><p>A protected space centered on LGBTQ+ stories and the people who shape them.</p></div><div class="profile-chip"><div class="avatar plum">{{(profile?.full_name||'TR').slice(0,2).toUpperCase()}}</div><div><strong>{{profile?.full_name}}</strong><small>{{profile?.role}}</small></div><button class="bare-icon" @click="signOut"><LogOut :size="17"/></button></div></aside>
    <main><header class="topbar"><button class="menu-button" @click="mobileNav=true"><Menu/></button><div><p class="eyebrow">AUTHOR WORKSPACE</p><h1>{{pageTitle}}</h1></div><div class="top-actions"><button class="icon-button"><Bell :size="19"/></button><button class="primary" @click="showNewBook=true"><Plus :size="18"/> New book</button></div></header>
      <section v-if="activeView==='dashboard'" class="content"><div class="welcome-row"><div><h2>Good to see you, {{profile?.full_name?.split(' ')[0]}}.</h2><p>{{newFeedback.length}} feedback notes are waiting for review.</p></div></div><div class="metric-grid"><article><span class="metric-icon violet"><BookOpen/></span><div><small>ACTIVE BOOKS</small><strong>{{activeBooks.length}}</strong><p>{{books.length}} total projects</p></div></article><article><span class="metric-icon teal"><Users/></span><div><small>ACTIVE READERS</small><strong>{{activeReaders.length}}</strong><p>Across your books</p></div></article><article><span class="metric-icon gold"><MessageSquare/></span><div><small>FEEDBACK</small><strong>{{feedback.length}}</strong><p>{{newFeedback.length}} need review</p></div></article><article><span class="metric-icon rose"><Gauge/></span><div><small>READER LIMIT</small><strong>10</strong><p>Per book</p></div></article></div><section class="panel projects-panel"><div class="panel-head"><div><p class="eyebrow">MANUSCRIPTS</p><h3>Your books</h3></div><button class="text-button" @click="changeView('books')">View all <ChevronRight :size="16"/></button></div><div v-if="!books.length" class="empty-state compact"><BookOpen/><h3>No books yet</h3><p>Upload your first manuscript to begin.</p><button class="primary" @click="showNewBook=true">Add manuscript</button></div><div v-for="book in books.slice(0,4)" :key="book.id" class="book-row"><div class="book-cover holiday"><BookOpen :size="18"/></div><div class="book-info"><h4>{{book.title}}</h4><p>{{book.genre||'Genre not set'}} · {{book.status}}</p></div><div class="book-stat"><strong>{{invitations.filter(i=>i.book_id===book.id&&!i.revoked_at).length}}/10</strong><small>readers</small></div><button class="secondary small-button" @click="openBook(book)">Preview</button></div></section></section>
      <section v-else-if="activeView==='books'" class="content"><div class="welcome-row"><div><h2>Manuscript projects</h2><p>Upload a Word document or paste your manuscript text.</p></div><button class="primary" @click="showNewBook=true"><Plus :size="18"/> Add book</button></div><div v-if="books.length" class="book-card-grid"><article v-for="book in books" :key="book.id" class="panel book-card"><div class="book-card-top"><div class="book-cover large holiday"><BookOpen/></div><span class="status" :class="book.status">{{book.status}}</span></div><p class="eyebrow">{{book.genre||'MANUSCRIPT'}}</p><h3>{{book.title}}</h3><p class="book-byline">{{book.author_name}}</p><div class="card-footer"><span><Users :size="16"/> {{invitations.filter(i=>i.book_id===book.id&&!i.revoked_at).length}}/10</span><button class="secondary" @click="startInvite(book.id)"><Send :size="15"/> Invite</button><button class="primary" @click="openBook(book)">Open</button></div></article></div><div v-else class="panel empty-state"><BookOpen/><h2>Your shelf is empty</h2><p>Create your first project with a DOCX file or pasted manuscript.</p><button class="primary" @click="showNewBook=true">Add your first book</button></div></section>
      <section v-else-if="activeView==='readers'" class="content"><div class="welcome-row"><div><h2>Reader directory</h2><p>Manage access separately for every manuscript.</p></div><button class="primary" :disabled="!books.length" @click="startInvite()"><Send :size="18"/> Invite reader</button></div><section class="panel data-panel"><div v-if="!invitations.length" class="empty-state"><Users/><h2>No readers invited</h2></div><template v-else><div class="reader-table-head"><span>READER</span><span>BOOK</span><span>STATUS</span><span>DEADLINE</span><span></span></div><div v-for="invite in invitations" :key="invite.id" class="reader-row"><div class="reader-cell"><span class="avatar">{{invite.email.slice(0,2).toUpperCase()}}</span><div><strong>{{invite.email}}</strong><small>{{invite.reader_id?'Account connected':'Waiting for sign-in'}}</small></div></div><span>{{books.find(b=>b.id===invite.book_id)?.title}}</span><span class="status" :class="invite.status">{{invite.status}}</span><small>{{invite.individual_deadline||'No date'}}</small><button v-if="!invite.revoked_at" class="danger-link" @click="revokeInvitation(invite)">Revoke</button></div></template></section></section>
      <section v-else-if="activeView==='feedback'" class="content"><div class="welcome-row"><div><h2>Feedback inbox</h2><p>Every note is tied to the reader who submitted it.</p></div></div><div v-if="feedback.length" class="feedback-list"><article v-for="item in feedback" :key="item.id" class="panel feedback-card"><div class="feedback-meta"><div class="reader-cell"><span class="avatar">{{(item.profiles?.full_name||item.profiles?.email||'R').slice(0,2).toUpperCase()}}</span><div><strong>{{item.profiles?.full_name||item.profiles?.email}}</strong><small>{{item.books?.title}} · {{item.chapters?.title}}</small></div></div><small>{{new Date(item.created_at).toLocaleDateString()}}</small></div><blockquote>“{{item.quoted_text}}”</blockquote><p>{{item.comment_text}}</p><div class="feedback-actions"><select :value="item.status" @change="updateStatus(item,$event.target.value)"><option v-for="s in ['new','consider','revise','accepted','dismissed']" :key="s" :value="s">{{s}}</option></select></div></article></div><div v-else class="panel empty-state"><MessageSquare/><h2>No feedback yet</h2><p>Reader comments will appear here.</p></div></section>
      <section v-else class="content"><div class="welcome-row"><div><h2>Workspace settings</h2><p>Your security controls apply to every reading session.</p></div></div><div class="settings-grid"><section class="panel settings-card"><h3>Manuscript protection</h3><div class="setting-confirm"><Check/> Author and reader watermark</div><div class="setting-confirm"><Check/> Copying and printing blocked</div><div class="setting-confirm"><Check/> Confidentiality agreement required</div></section><section class="panel settings-card"><h3>Owner account</h3><p>{{OWNER_EMAIL}}</p><p class="muted-copy">New accounts default to reader access.</p></section></div></section>
    </main>
  </div>

  <div v-if="showNewBook" class="modal-backdrop" @click.self="showNewBook=false"><section class="modal"><button class="modal-close" @click="showNewBook=false"><X/></button><p class="eyebrow">NEW PROJECT</p><h2>Add your manuscript.</h2><p>Upload DOCX or TXT, or paste the manuscript. “Chapter 1” headings are detected automatically.</p><label>Book title<input v-model="newBook.title" placeholder="Working title"/></label><div class="form-grid"><label>Author name<input v-model="newBook.author_name"/></label><label>Genre<input v-model="newBook.genre" placeholder="LGBTQ+ Romance"/></label></div><label>Overall deadline<input v-model="newBook.deadline" type="date"/></label><label class="file-drop"><Upload/><strong>{{newBook.file?.name||'Choose DOCX or TXT file'}}</strong><small>Maximum 20 MB</small><input type="file" accept=".docx,.txt" @change="handleFile"/></label><div class="or"><span>OR PASTE TEXT</span></div><label>Manuscript text<textarea v-model="newBook.manuscriptText" rows="7" placeholder="Chapter 1&#10;&#10;Paste manuscript text here…"></textarea></label><button class="primary full" :disabled="actionLoading" @click="createBook">{{actionLoading?'Creating project…':'Create manuscript project'}}</button></section></div>
  <div v-if="showInvite" class="modal-backdrop" @click.self="showInvite=false"><section class="modal compact"><button class="modal-close" @click="showInvite=false"><X/></button><p class="eyebrow">READER ACCESS</p><h2>Invite a trusted reader.</h2><p>Use the exact email address the reader will use to sign in.</p><label>Reader email<input v-model="newInvite.email" type="email" placeholder="reader@example.com"/></label><label>Book<select v-model="newInvite.book_id"><option disabled value="">Choose a book</option><option v-for="book in books" :key="book.id" :value="book.id">{{book.title}}</option></select></label><label>Individual deadline<input v-model="newInvite.deadline" type="date"/></label><button class="primary full" :disabled="actionLoading" @click="inviteReader">{{actionLoading?'Creating access…':'Create reader access'}}</button></section></div>
  <div v-if="showAgreement" class="modal-backdrop highest"><section class="modal agreement-modal"><ShieldCheck :size="34"/><p class="eyebrow">CONFIDENTIALITY AGREEMENT</p><h2>Protect the work in this room.</h2><p>By opening this manuscript, you agree not to copy, download, print, distribute, train an AI system on, or publicly discuss any part of it. Access is personal and may be revoked by the author.</p><button class="primary full" @click="acceptAgreement">I agree and will protect this manuscript</button><button class="text-button cancel-agreement" @click="showAgreement=false;selectedBook=null">Decline and leave</button></section></div>
  <div v-if="showReader" class="reader-overlay"><header class="reader-header"><button class="reader-back" @click="showReader=false"><ChevronLeft :size="18"/> Exit reader</button><div><strong>{{selectedBook?.title}}</strong><small>{{selectedChapter?.title||'No chapters'}}</small></div><div class="reader-tools"><span><LockKeyhole :size="15"/> Protected session</span></div></header><div class="reader-progress"><i :style="{width:chapters.length?`${((chapters.findIndex(c=>c.id===selectedChapter?.id)+1)/chapters.length)*100}%`:'0%'}"></i></div><main class="manuscript-wrap"><aside class="chapter-rail"><p class="eyebrow">CONTENTS</p><button v-for="chapter in chapters" :key="chapter.id" :class="{active:chapter.id===selectedChapter?.id}" @click="selectedChapter=chapter"><span>{{chapter.chapter_number}}</span><div><strong>{{chapter.title}}</strong></div></button></aside><article class="manuscript"><div class="watermarks"><span v-for="n in 12" :key="n">{{selectedBook?.author_name?.toUpperCase()}} · {{readerEmail}}</span></div><template v-if="selectedChapter"><p class="chapter-number">CHAPTER {{selectedChapter.chapter_number}}</p><h1>{{selectedChapter.title}}</h1><p v-if="!isAuthor" class="reader-instruction"><MessageSquare :size="15"/> Click any sentence to comment.</p><div class="prose"><button v-for="(sentence,index) in chapterSentences" :key="index" @click="openSentence(sentence,index)">{{sentence}} </button></div><div v-if="!isAuthor" class="chapter-end"><Check/><h3>Reached the end?</h3><button class="primary" @click="completeChapter">Complete chapter</button></div></template><div v-else class="empty-state"><FileText/><h2>No chapters found</h2></div></article></main><div v-if="showNotice" class="protection-notice"><ShieldCheck/><div><strong>This manuscript is protected.</strong><span>Copying, printing, and screenshots are not permitted.</span></div></div></div>
  <div v-if="showComment" class="modal-backdrop highest" @click.self="showComment=false"><section class="modal compact"><button class="modal-close" @click="showComment=false"><X/></button><p class="eyebrow">INLINE COMMENT</p><blockquote>“{{selectedSentence}}”</blockquote><label>Your note<textarea v-model="commentText" autofocus></textarea></label><button class="primary full" :disabled="actionLoading" @click="submitComment">Save comment</button></section></div>
  <Transition name="toast"><div v-if="toast" class="toast"><Check :size="17"/>{{toast}}</div></Transition>
</template>
