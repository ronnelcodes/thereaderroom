<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import {
  Bell, BookOpen, Check, ChevronDown, ChevronLeft, ChevronRight, CircleHelp,
  Clock3, FileText, Gauge, Inbox, LayoutDashboard, LockKeyhole, Menu, MessageSquare,
  MoreHorizontal, Plus, Search, Send, Settings, ShieldCheck, Sparkles, Upload,
  UserRound, Users, X
} from 'lucide-vue-next'

const activeView = ref('dashboard')
const mobileNav = ref(false)
const showNewBook = ref(false)
const showInvite = ref(false)
const showReader = ref(false)
const showComment = ref(false)
const showNotice = ref(false)
const selectedSentence = ref('')
const toast = ref('')
let webMcpController

const nav = [
  { id: 'dashboard', label: 'Overview', icon: LayoutDashboard },
  { id: 'books', label: 'Books', icon: BookOpen },
  { id: 'readers', label: 'Readers', icon: Users },
  { id: 'feedback', label: 'Feedback', icon: MessageSquare },
  { id: 'settings', label: 'Settings', icon: Settings }
]

const books = ref([
  { title: 'Borrowed for the Holidays', genre: 'LGBTQ+ Romance', readers: 3, limit: 10, progress: 68, feedback: 47, status: 'Active', due: 'Oct 12, 2026' },
  { title: 'Closeted Hearts', genre: 'Contemporary Romance', readers: 2, limit: 10, progress: 31, feedback: 18, status: 'Active', due: 'Oct 30, 2026' },
  { title: 'Uncloseted Hearts', genre: 'LGBTQ+ Romance', readers: 0, limit: 10, progress: 0, feedback: 0, status: 'Draft', due: 'Not set' }
])

const readers = ref([
  { name: 'Marcus Ellis', email: 'marcus@example.com', book: 'Borrowed for the Holidays', progress: 92, activity: '18 min ago', feedback: 21, status: 'Reading' },
  { name: 'Jordan Lee', email: 'jordan@example.com', book: 'Borrowed for the Holidays', progress: 71, activity: 'Yesterday', feedback: 16, status: 'Reading' },
  { name: 'Elliot Rivera', email: 'elliot@example.com', book: 'Borrowed for the Holidays', progress: 42, activity: '3 days ago', feedback: 10, status: 'Reading' },
  { name: 'Casey Brooks', email: 'casey@example.com', book: 'Closeted Hearts', progress: 38, activity: '2 hours ago', feedback: 12, status: 'Reading' },
  { name: 'Devon Shah', email: 'devon@example.com', book: 'Closeted Hearts', progress: 24, activity: '5 days ago', feedback: 6, status: 'Reading' }
])

const feedback = ref([
  { id: 1, reader: 'Marcus Ellis', initials: 'ME', book: 'Borrowed for the Holidays', chapter: 'Chapter 12', quote: 'Rafe set the plate between them like an offering.', note: 'This image is gorgeous. It also feels like the exact moment August realizes this has stopped being pretend.', status: 'New', when: '18 min ago' },
  { id: 2, reader: 'Jordan Lee', initials: 'JL', book: 'Borrowed for the Holidays', chapter: 'Chapter 9', quote: 'The kitchen had never felt this small before.', note: 'Could we get one more physical detail here to heighten the tension?', status: 'Consider', when: 'Yesterday' },
  { id: 3, reader: 'Casey Brooks', initials: 'CB', book: 'Closeted Hearts', chapter: 'Chapter 4', quote: 'Evan looked toward the sanctuary doors.', note: 'The conflict is clear, but I wanted to understand what he fears losing most.', status: 'Revise', when: '2 days ago' }
])

const title = computed(() => nav.find(item => item.id === activeView.value)?.label || 'Overview')
const totalFeedback = computed(() => feedback.value.length + 62)

const sentences = [
  'August had spent most of his life believing a good plan could save him from embarrassment.',
  'Lists helped. Calendars helped more.',
  'But neither had prepared him for Rafe Mendez standing in the doorway of Second Story Books with rain darkening his shoulders and a smile that made every careful thought disappear.',
  '“You said this was an emergency,” Rafe said.',
  'August looked down at the contract on the counter. “It is.”'
]

function flash(message) {
  toast.value = message
  window.setTimeout(() => { toast.value = '' }, 2600)
}

function changeView(id) {
  activeView.value = id
  mobileNav.value = false
}

function openSentence(sentence) {
  selectedSentence.value = sentence
  showComment.value = true
}

function submitComment() {
  showComment.value = false
  flash('Comment saved to Chapter 1')
}

function addBook() {
  showNewBook.value = false
  flash('Project created. Add chapters when you are ready.')
}

function inviteReader() {
  showInvite.value = false
  flash('Invitation scheduled with email verification.')
}

function blockProtectedAction(event) {
  if (!showReader.value) return
  const key = event.key.toLowerCase()
  const blocked = (event.ctrlKey || event.metaKey) && ['c', 'x', 'a', 'p', 's', 'u'].includes(key)
  if (blocked || event.key === 'PrintScreen') {
    event.preventDefault()
    showNotice.value = true
    window.setTimeout(() => { showNotice.value = false }, 1800)
  }
}

function blockContext(event) {
  if (showReader.value) {
    event.preventDefault()
    showNotice.value = true
    window.setTimeout(() => { showNotice.value = false }, 1800)
  }
}

onMounted(() => {
  window.addEventListener('keydown', blockProtectedAction)
  window.addEventListener('contextmenu', blockContext)

  const context = document.modelContext
  if (context?.registerTool) {
    webMcpController = new AbortController()
    const options = { signal: webMcpController.signal }
    Promise.resolve(context.registerTool({
      name: 'start_book_creation',
      title: 'Start book creation',
      description: 'Open the visible form for starting a new manuscript project.',
      inputSchema: { type: 'object', properties: {}, additionalProperties: false },
      annotations: { readOnlyHint: false, untrustedContentHint: false },
      execute() {
        activeView.value = 'books'
        showNewBook.value = true
        return { view: 'books', form: 'new-book', status: 'opened' }
      }
    }, options)).catch(() => {})
    Promise.resolve(context.registerTool({
      name: 'start_reader_invitation',
      title: 'Start reader invitation',
      description: 'Open the visible form for inviting a beta reader by email.',
      inputSchema: { type: 'object', properties: {}, additionalProperties: false },
      annotations: { readOnlyHint: false, untrustedContentHint: false },
      execute() {
        activeView.value = 'readers'
        showInvite.value = true
        return { view: 'readers', form: 'invite-reader', status: 'opened' }
      }
    }, options)).catch(() => {})
  }
})

onBeforeUnmount(() => {
  window.removeEventListener('keydown', blockProtectedAction)
  window.removeEventListener('contextmenu', blockContext)
  webMcpController?.abort()
})
</script>

<template>
  <div class="app-shell">
    <aside class="sidebar" :class="{ open: mobileNav }">
      <button class="mobile-close" aria-label="Close menu" @click="mobileNav = false"><X :size="22" /></button>
      <div class="brand">
        <div class="brand-mark">V<span>&</span>V</div>
        <div><strong>THE READER ROOM</strong><small>Vibe & Vision Collective</small></div>
      </div>

      <nav aria-label="Main navigation">
        <button v-for="item in nav" :key="item.id" :class="{ active: activeView === item.id }" @click="changeView(item.id)">
          <component :is="item.icon" :size="19" /><span>{{ item.label }}</span>
          <span v-if="item.id === 'feedback'" class="nav-count">12</span>
        </button>
      </nav>

      <div class="collective-card">
        <Sparkles :size="18" />
        <strong>Creative community</strong>
        <p>A protected space centered on LGBTQ+ stories and the people who shape them.</p>
      </div>

      <div class="profile-chip">
        <div class="avatar plum">TD</div>
        <div><strong>Teejaye Deloach</strong><small>Author</small></div>
        <MoreHorizontal :size="18" />
      </div>
    </aside>

    <main>
      <header class="topbar">
        <button class="menu-button" aria-label="Open menu" @click="mobileNav = true"><Menu :size="22" /></button>
        <div><p class="eyebrow">AUTHOR WORKSPACE</p><h1>{{ title }}</h1></div>
        <div class="top-actions">
          <label class="search"><Search :size="17" /><input aria-label="Search" placeholder="Search feedback" /></label>
          <button class="icon-button" aria-label="Notifications"><Bell :size="19" /><span></span></button>
          <button class="primary" @click="showNewBook = true"><Plus :size="18" /> New book</button>
        </div>
      </header>

      <section v-if="activeView === 'dashboard'" class="content dashboard">
        <div class="welcome-row">
          <div><h2>Good morning, Teejaye.</h2><p>Your readers left 7 new notes since yesterday.</p></div>
          <button class="secondary" @click="showReader = true"><ShieldCheck :size="18" /> Preview protected reader view</button>
        </div>

        <div class="metric-grid">
          <article><span class="metric-icon violet"><BookOpen /></span><div><small>ACTIVE BOOKS</small><strong>2</strong><p>1 draft waiting</p></div></article>
          <article><span class="metric-icon teal"><Users /></span><div><small>ACTIVE READERS</small><strong>5</strong><p>Across 2 projects</p></div></article>
          <article><span class="metric-icon gold"><MessageSquare /></span><div><small>FEEDBACK</small><strong>{{ totalFeedback }}</strong><p>12 need review</p></div></article>
          <article><span class="metric-icon rose"><Gauge /></span><div><small>AVG. PROGRESS</small><strong>61%</strong><p>Readers are on pace</p></div></article>
        </div>

        <div class="dashboard-grid">
          <section class="panel projects-panel">
            <div class="panel-head"><div><p class="eyebrow">IN PROGRESS</p><h3>Your books</h3></div><button class="text-button" @click="changeView('books')">View all <ChevronRight :size="16" /></button></div>
            <div v-for="book in books.slice(0,2)" :key="book.title" class="book-row">
              <div class="book-cover" :class="book.title.includes('Borrowed') ? 'holiday' : 'closeted'"><span>{{ book.title.split(' ').map(w=>w[0]).join('').slice(0,3) }}</span></div>
              <div class="book-info"><div><h4>{{ book.title }}</h4><p>{{ book.genre }} · Due {{ book.due }}</p></div><div class="progress-line"><span><i :style="{ width: `${book.progress}%` }"></i></span><strong>{{ book.progress }}%</strong></div></div>
              <div class="reader-stack"><span>ME</span><span>JL</span><span>ER</span></div>
              <div class="book-stat"><strong>{{ book.feedback }}</strong><small>notes</small></div>
              <button class="icon-button"><MoreHorizontal :size="20" /></button>
            </div>
          </section>

          <aside class="panel activity-panel">
            <div class="panel-head"><div><p class="eyebrow">LIVE</p><h3>Recent activity</h3></div></div>
            <div class="activity"><span class="avatar teal-bg">ME</span><p><strong>Marcus</strong> commented on Chapter 12<small>18 minutes ago</small></p></div>
            <div class="activity"><span class="activity-icon"><Check :size="16" /></span><p><strong>Jordan</strong> finished Chapter 9<small>Yesterday at 8:42 PM</small></p></div>
            <div class="activity"><span class="avatar gold-bg">CB</span><p><strong>Casey</strong> answered a questionnaire<small>Yesterday at 4:10 PM</small></p></div>
            <div class="activity"><span class="activity-icon"><Send :size="15" /></span><p>Reminder sent to <strong>Devon</strong><small>2 days ago</small></p></div>
          </aside>
        </div>

        <section class="panel feedback-preview">
          <div class="panel-head"><div><p class="eyebrow">LATEST NOTES</p><h3>Feedback to review</h3></div><button class="text-button" @click="changeView('feedback')">Open feedback inbox <ChevronRight :size="16" /></button></div>
          <div class="feedback-table-head"><span>READER</span><span>PASSAGE & NOTE</span><span>STATUS</span><span>RECEIVED</span></div>
          <div v-for="item in feedback.slice(0,2)" :key="item.id" class="feedback-row">
            <div class="reader-cell"><span class="avatar">{{ item.initials }}</span><div><strong>{{ item.reader }}</strong><small>{{ item.chapter }}</small></div></div>
            <div class="note-cell"><blockquote>“{{ item.quote }}”</blockquote><p>{{ item.note }}</p></div>
            <span class="status" :class="item.status.toLowerCase()">{{ item.status }}</span>
            <small>{{ item.when }}</small>
          </div>
        </section>
      </section>

      <section v-else-if="activeView === 'books'" class="content">
        <div class="welcome-row"><div><h2>Manuscript projects</h2><p>Upload a DOCX or create and organize chapters manually.</p></div><button class="primary" @click="showNewBook = true"><Plus :size="18" /> Add book</button></div>
        <div class="book-card-grid">
          <article v-for="book in books" :key="book.title" class="panel book-card">
            <div class="book-card-top"><div class="book-cover large" :class="book.title.includes('Borrowed') ? 'holiday' : 'closeted'"><span>{{ book.title.split(' ').map(w=>w[0]).join('').slice(0,3) }}</span></div><span class="status" :class="book.status.toLowerCase()">{{ book.status }}</span></div>
            <p class="eyebrow">{{ book.genre }}</p><h3>{{ book.title }}</h3>
            <div class="card-progress"><span><i :style="{ width: `${book.progress}%` }"></i></span><small>{{ book.progress }}% average progress</small></div>
            <div class="card-footer"><span><Users :size="16" /> {{ book.readers }}/{{ book.limit }}</span><span><MessageSquare :size="16" /> {{ book.feedback }}</span><button class="secondary" @click="showReader = true">Open</button></div>
          </article>
          <button class="new-card" @click="showNewBook = true"><Plus :size="30" /><strong>Start a new book</strong><span>Upload DOCX or enter chapters</span></button>
        </div>
      </section>

      <section v-else-if="activeView === 'readers'" class="content">
        <div class="welcome-row"><div><h2>Reader directory</h2><p>Monitor access, activity, progress, and feedback separately.</p></div><button class="primary" @click="showInvite = true"><Send :size="18" /> Invite reader</button></div>
        <section class="panel data-panel">
          <div class="filter-row"><label class="search wide"><Search :size="17" /><input placeholder="Search readers" /></label><button class="secondary">All books <ChevronDown :size="16" /></button><button class="secondary">All activity <ChevronDown :size="16" /></button></div>
          <div class="reader-table-head"><span>READER</span><span>BOOK</span><span>PROGRESS</span><span>FEEDBACK</span><span>LAST ACTIVE</span><span></span></div>
          <div v-for="reader in readers" :key="reader.email" class="reader-row">
            <div class="reader-cell"><span class="avatar">{{ reader.name.split(' ').map(n=>n[0]).join('') }}</span><div><strong>{{ reader.name }}</strong><small>{{ reader.email }}</small></div></div>
            <span>{{ reader.book }}</span><div class="mini-progress"><span><i :style="{width:`${reader.progress}%`}"></i></span><strong>{{ reader.progress }}%</strong></div><span>{{ reader.feedback }} notes</span><small>{{ reader.activity }}</small><button class="icon-button"><MoreHorizontal :size="20" /></button>
          </div>
        </section>
      </section>

      <section v-else-if="activeView === 'feedback'" class="content">
        <div class="welcome-row"><div><h2>Feedback inbox</h2><p>Review, categorize, and turn reader notes into your revision plan.</p></div><button class="secondary"><FileText :size="18" /> Export PDF or CSV</button></div>
        <div class="feedback-layout">
          <aside class="panel filters"><p class="eyebrow">FILTER BY STATUS</p><button class="active"><Inbox :size="17" /> All feedback <span>65</span></button><button><span class="dot new"></span>New <span>12</span></button><button><span class="dot consider"></span>Consider <span>24</span></button><button><span class="dot revise"></span>Revise <span>18</span></button><button><span class="dot accepted"></span>Accepted <span>8</span></button><button><span class="dot dismissed"></span>Dismissed <span>3</span></button></aside>
          <section class="feedback-list">
            <article v-for="item in feedback" :key="item.id" class="panel feedback-card">
              <div class="feedback-meta"><div class="reader-cell"><span class="avatar">{{ item.initials }}</span><div><strong>{{ item.reader }}</strong><small>{{ item.book }} · {{ item.chapter }}</small></div></div><small>{{ item.when }}</small></div>
              <blockquote>“{{ item.quote }}”</blockquote><p>{{ item.note }}</p>
              <div class="feedback-actions"><button class="status" :class="item.status.toLowerCase()">{{ item.status }} <ChevronDown :size="14" /></button><button class="text-button">Add private note</button><button class="text-button">Reply</button></div>
            </article>
          </section>
        </div>
      </section>

      <section v-else class="content settings-view">
        <div class="welcome-row"><div><h2>Workspace settings</h2><p>Control your author identity, reader terms, reminders, and manuscript protection.</p></div><button class="primary" @click="flash('Settings saved')">Save changes</button></div>
        <div class="settings-grid">
          <section class="panel settings-card"><h3>Manuscript protection</h3><p>Applied to every protected reading session.</p><label class="toggle-row"><span><strong>Personalized watermarks</strong><small>Author name and reader email repeat across each page.</small></span><input type="checkbox" checked /><i></i></label><label class="toggle-row"><span><strong>Block copy and selection</strong><small>Disable selection, right-click, printing, and common shortcuts.</small></span><input type="checkbox" checked /><i></i></label><label class="toggle-row"><span><strong>Confidentiality agreement</strong><small>Require acceptance before first access.</small></span><input type="checkbox" checked /><i></i></label></section>
          <section class="panel settings-card"><h3>Automated messages</h3><p>Authors can customize the timing and wording for each book.</p><label>Reminder cadence<select><option>7 days, 3 days, and deadline day</option></select></label><label>Completion message<textarea>Thank you for completing this beta read. Your thoughtful feedback helps shape the next draft.</textarea></label></section>
        </div>
      </section>
    </main>

    <div v-if="showNewBook" class="modal-backdrop" @click.self="showNewBook = false">
      <section class="modal" role="dialog" aria-modal="true" aria-label="Create a new book"><button class="modal-close" @click="showNewBook = false"><X /></button><p class="eyebrow">NEW PROJECT</p><h2>Bring your manuscript in.</h2><p>Start with a Word document or build the book chapter by chapter.</p><div class="method-grid"><button class="upload-method"><Upload /><strong>Upload DOCX</strong><span>We’ll detect and organize chapters.</span></button><button class="upload-method"><FileText /><strong>Enter chapters</strong><span>Paste and format your manuscript manually.</span></button></div><label>Book title<input value="" placeholder="Working title" /></label><label>Author name<input value="Teejaye Deloach" /></label><button class="primary full" @click="addBook">Create project</button></section>
    </div>

    <div v-if="showInvite" class="modal-backdrop" @click.self="showInvite = false">
      <section class="modal" role="dialog" aria-modal="true" aria-label="Invite a beta reader"><button class="modal-close" @click="showInvite = false"><X /></button><p class="eyebrow">READER INVITATION</p><h2>Invite a trusted reader.</h2><p>They’ll receive a private invitation and sign in with an email verification code.</p><label>Reader email<input type="email" placeholder="reader@example.com" /></label><label>Book<select><option>Borrowed for the Holidays</option><option>Closeted Hearts</option></select></label><label>Individual deadline<input type="date" value="2026-10-12" /></label><button class="primary full" @click="inviteReader"><Send :size="17" /> Send invitation</button></section>
    </div>

    <div v-if="showReader" class="reader-overlay" @contextmenu.prevent>
      <header class="reader-header"><button class="reader-back" @click="showReader = false"><ChevronLeft :size="18" /> Exit preview</button><div><strong>Borrowed for the Holidays</strong><small>Chapter 1 · The Proposal</small></div><div class="reader-tools"><span><LockKeyhole :size="15" /> Protected session</span><button class="icon-button"><CircleHelp :size="19" /></button></div></header>
      <div class="reader-progress"><i style="width: 8%"></i></div>
      <main class="manuscript-wrap">
        <aside class="chapter-rail"><p class="eyebrow">CONTENTS</p><button class="active"><span>1</span><div><strong>The Proposal</strong><small>Reading</small></div></button><button><span>2</span><div><strong>Terms & Conditions</strong><small>Not started</small></div></button><button><span>3</span><div><strong>Halloween</strong><small>Not started</small></div></button></aside>
        <article class="manuscript" aria-label="Protected manuscript">
          <div class="watermarks" aria-hidden="true"><span v-for="n in 12" :key="n">TEEJAYE DELOACH · marcus@example.com</span></div>
          <p class="chapter-number">CHAPTER ONE</p><h1>The Proposal</h1><p class="reader-instruction"><MessageSquare :size="15" /> Click any sentence to leave an inline comment.</p>
          <div class="prose"><button v-for="sentence in sentences" :key="sentence" @click="openSentence(sentence)">{{ sentence }}</button></div>
          <div class="chapter-end"><Check :size="24" /><h3>Reached the end of Chapter 1?</h3><p>Mark it complete to open the chapter questionnaire.</p><button class="primary" @click="flash('Chapter marked complete')">Complete chapter</button></div>
        </article>
        <aside class="comment-rail"><div class="comment-head"><strong>Chapter notes</strong><span>2</span></div><article><div><span class="avatar small">ME</span><strong>You</strong><small>12 min ago</small></div><p>The rhythm here makes August’s anxiety feel immediate.</p></article><article><div><span class="avatar small plum">TD</span><strong>Teejaye</strong><small>5 min ago</small></div><p>That’s helpful. I may carry the shorter sentences into the next beat.</p></article></aside>
      </main>
      <div v-if="showNotice" class="protection-notice"><ShieldCheck /><div><strong>This manuscript is protected.</strong><span>Copying, printing, and screenshots are not permitted.</span></div></div>
    </div>

    <div v-if="showComment" class="modal-backdrop highest" @click.self="showComment = false"><section class="modal compact"><button class="modal-close" @click="showComment = false"><X /></button><p class="eyebrow">INLINE COMMENT</p><blockquote>“{{ selectedSentence }}”</blockquote><label>Your note<textarea autofocus placeholder="What stood out to you?"></textarea></label><button class="primary full" @click="submitComment">Save comment</button></section></div>

    <Transition name="toast"><div v-if="toast" class="toast"><Check :size="17" />{{ toast }}</div></Transition>
  </div>
</template>
