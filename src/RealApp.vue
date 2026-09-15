<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { ArrowDown, ArrowUp, Bell, BookOpen, Check, ChevronLeft, ChevronRight, Eye, EyeOff, FileText, Gauge, Inbox, LayoutDashboard, LockKeyhole, LogOut, Menu, MessageSquare, Pencil, Plus, Scissors, Send, Settings, ShieldCheck, Sparkles, Trash2, Upload, Users, X } from 'lucide-vue-next'
import pdfWorkerUrl from 'pdfjs-dist/build/pdf.worker.min.mjs?url'
import { isSupabaseConfigured, supabase } from './lib/supabase'

const OWNER_EMAIL = 'thereaderroom@teejayedeloach.com'
const initialPortal = window.location.pathname.startsWith('/admin-login') ? 'admin' : window.location.pathname.startsWith('/author-login') ? 'author' : window.location.pathname.startsWith('/reader-login') ? 'reader' : 'choice'
const loading = ref(true), actionLoading = ref(false)
const session = ref(null), profile = ref(null)
const portal = ref(initialPortal)
const authEmail = ref(''), authPassword = ref(''), authCode = ref(''), codeSent = ref(false), authMode = ref('password'), authError = ref(''), errorMessage = ref('')
const newPassword = ref(''), confirmPassword = ref(''), passwordSetupRequired = ref(sessionStorage.getItem('readerRoomPasswordSetup')==='true')
const showAuthPassword = ref(false), showNewPassword = ref(false), showConfirmPassword = ref(false)
const activeView = ref('dashboard'), mobileNav = ref(false), toast = ref('')
const books = ref([]), invitations = ref([]), feedback = ref([]), chapters = ref([])
const authorInvitations = ref([]), people = ref([]), newAuthorEmail = ref('')
const newPerson = ref({full_name:'',email:'',role:'author',temp_password:'',book_id:''}), createdAccount = ref(null), showTempPassword = ref(false)
const selectedBook = ref(null), selectedChapter = ref(null)
const showNewBook = ref(false), showChapterReview = ref(false), showInvite = ref(false), showReader = ref(false), showAgreement = ref(false), showComment = ref(false), showNotice = ref(false)
const selectedSentence = ref(''), selectedSentenceIndex = ref(null), commentText = ref('')
const newBook = ref({ title:'', author_name:'Teejaye Deloach', genre:'', description:'', deadline:'', manuscriptText:'', files:[] })
const reviewMode = ref('create'), reviewBook = ref(null), reviewChapters = ref([])
const newInvite = ref({ email:'', book_id:'', deadline:'' })
const chapterTextareas = new Map()
let authSubscription

const genreGroups = [
  {label:'Fiction',options:['Action & Adventure','African American Fiction','Anthology','Children’s Fiction','Christian Fiction','Classics','Coming of Age','Contemporary Fiction','Crime Fiction','Dark Academia','Dystopian Fiction','Erotica','Family Saga','Fantasy','Gothic Fiction','Historical Fiction','Holiday Fiction','Horror','Humor & Satire','LGBTQ+ Fiction','LGBTQ+ Romance','Literary Fiction','Magical Realism','Mystery','New Adult','Paranormal Fiction','Romance','Romance - Contemporary','Romance - Fantasy','Romance - Historical','Romance - Holiday','Romance - Paranormal','Romance - Romantic Suspense','Romantic Comedy','Science Fiction','Short Stories','Speculative Fiction','Sports Fiction','Supernatural Fiction','Suspense','Thriller','Urban Fiction','Western','Women’s Fiction','Young Adult','Young Adult Romance']},
  {label:'Nonfiction',options:['Art & Photography','Biography & Memoir','Business & Economics','Christian Living','Computers & Technology','Cookbooks, Food & Wine','Crafts & Hobbies','Education & Teaching','Essays','Family & Relationships','Health & Wellness','History','Home & Garden','Humor','LGBTQ+ Nonfiction','Music','Nature & Environment','Parenting','Personal Development','Philosophy','Politics & Social Sciences','Psychology','Religion & Spirituality','Science & Mathematics','Self-Help','Sports & Recreation','Travel','True Crime']},
  {label:'Other',options:['Poetry','Graphic Novel & Comics','Reference','Other']}
]
const statusOptions = ['draft','active','complete','archived']

const isAdmin = computed(()=>profile.value?.role==='admin')
const isAuthor = computed(()=>['admin','author'].includes(profile.value?.role))
const nav = computed(()=>[
  {id:'dashboard',label:'Overview',icon:LayoutDashboard},{id:'books',label:'Books',icon:BookOpen},
  ...(isAdmin.value?[{id:'authors',label:'People',icon:Users}]:[]),
  {id:'readers',label:'Readers',icon:Users},{id:'feedback',label:'Feedback',icon:MessageSquare},{id:'settings',label:'Settings',icon:Settings}
])
const wrongPortal = computed(()=>session.value&&profile.value&&((portal.value==='admin'&&!isAdmin.value)||(portal.value==='author'&&profile.value.role!=='author')||(portal.value==='reader'&&profile.value.role!=='reader')))
const pageTitle = computed(()=>nav.value.find(i=>i.id===activeView.value)?.label||'Overview')
const activeBooks = computed(()=>books.value.filter(b=>b.status==='active'))
const activeReaders = computed(()=>invitations.value.filter(i=>!i.revoked_at&&i.status!=='revoked'))
const newFeedback = computed(()=>feedback.value.filter(i=>i.status==='new'))
const readerInvitations = computed(()=>invitations.value.filter(i=>i.reader_id===session.value?.user?.id||i.email?.toLowerCase()===session.value?.user?.email?.toLowerCase()))
const readerEmail = computed(()=>session.value?.user?.email||'')
const chapterSentences = computed(()=> (selectedChapter.value?.content||'').split(/(?<=[.!?])\s+(?=[A-Z“"'])/).filter(Boolean))
const passwordRules = computed(()=>({length:newPassword.value.length>=10,capital:/[A-Z]/.test(newPassword.value),lowercase:/[a-z]/.test(newPassword.value),number:/\d/.test(newPassword.value),special:/[^A-Za-z0-9]/.test(newPassword.value)}))
const passwordIsValid = computed(()=>Object.values(passwordRules.value).every(Boolean)&&newPassword.value===confirmPassword.value)
const temporaryPasswordIsValid = computed(()=>newPerson.value.temp_password.length>=10&&/[A-Z]/.test(newPerson.value.temp_password)&&/[a-z]/.test(newPerson.value.temp_password)&&/\d/.test(newPerson.value.temp_password)&&/[^A-Za-z0-9]/.test(newPerson.value.temp_password))

function flash(message){toast.value=message;setTimeout(()=>toast.value='',2800)}
function changeView(id){if(id!=='authors')createdAccount.value=null;activeView.value=id;mobileNav.value=false}
function resetAuthForm(){authPassword.value='';authCode.value='';codeSent.value=false;authMode.value='password';authError.value='';showAuthPassword.value=false;showNewPassword.value=false;showConfirmPassword.value=false}
function selectPortal(kind){portal.value=kind;authEmail.value='';resetAuthForm();window.history.replaceState({},'',`/${kind}-login`)}
function portalHome(){portal.value='choice';authEmail.value='';resetAuthForm();window.history.replaceState({},'','/')}
function setupPassword(){authMode.value='setup';authPassword.value='';authCode.value='';codeSent.value=false;authError.value=''}

async function checkPortalEmail(email){
  const gateFunction={admin:'can_use_admin_portal',author:'can_use_author_portal',reader:'can_use_reader_portal'}[portal.value]
  const gate=await supabase.rpc(gateFunction,{candidate_email:email})
  if(gate.error||!gate.data)throw new Error(portal.value==='admin'?'This email is not approved for administrator access.':portal.value==='author'?'This email is not approved for author access.':'This email is not approved for reader access.')
}

async function signInWithPassword(){
  authError.value='';if(!authEmail.value.trim()||!authPassword.value)return authError.value='Enter your email address and password.'
  actionLoading.value=true
  try{
    const email=authEmail.value.trim().toLowerCase();await checkPortalEmail(email)
    const {error}=await supabase.auth.signInWithPassword({email,password:authPassword.value});if(error)throw error
  }catch(error){authError.value=error.message==='Invalid login credentials'?'The email or password is incorrect.':error.message}
  finally{actionLoading.value=false}
}

async function sendCode(){
  authError.value=''; if(!authEmail.value.trim()||portal.value==='choice')return
  actionLoading.value=true
  const email=authEmail.value.trim().toLowerCase()
  try{
    await checkPortalEmail(email)
    const {error}=await supabase.auth.signInWithOtp({email,options:{shouldCreateUser:true,emailRedirectTo:`${window.location.origin}/${portal.value}-login`,data:{full_name:email.split('@')[0]}}});if(error)throw error
    codeSent.value=true
  }catch(error){authError.value=error.message}
  finally{actionLoading.value=false}
}
async function verifyCode(){
  authError.value='';actionLoading.value=true;passwordSetupRequired.value=true;sessionStorage.setItem('readerRoomPasswordSetup','true')
  const {data,error}=await supabase.auth.verifyOtp({email:authEmail.value.trim().toLowerCase(),token:authCode.value.trim(),type:'email'})
  actionLoading.value=false
  if(error){passwordSetupRequired.value=false;sessionStorage.removeItem('readerRoomPasswordSetup');authError.value=error.message;return}
  session.value=data.session;newPassword.value='';confirmPassword.value=''
}
async function savePassword(){
  authError.value=''
  if(!passwordIsValid.value){authError.value=newPassword.value!==confirmPassword.value?'The passwords do not match.':'Your password does not meet every requirement.';return}
  actionLoading.value=true
  const {error}=await supabase.auth.updateUser({password:newPassword.value})
  if(error){actionLoading.value=false;authError.value=error.message;return}
  const marked=await supabase.rpc('mark_password_set')
  if(marked.error){actionLoading.value=false;authError.value='The password was saved, but account setup could not finish. Run the password-authentication SQL update and try again.';return}
  await supabase.auth.signOut();actionLoading.value=false;session.value=null;profile.value=null;passwordSetupRequired.value=false;sessionStorage.removeItem('readerRoomPasswordSetup');newPassword.value='';confirmPassword.value='';authMode.value='password';codeSent.value=false;authPassword.value='';flash('Password saved. Sign in with your new password.')
}
async function signOut(){passwordSetupRequired.value=false;sessionStorage.removeItem('readerRoomPasswordSetup');await supabase.auth.signOut();profile.value=null;books.value=[];invitations.value=[];feedback.value=[];people.value=[]}

async function loadWorkspace(){
  if(!session.value)return;loading.value=true;errorMessage.value=''
  try{
    const {data:p,error:pe}=await supabase.from('profiles').select('*').eq('id',session.value.user.id).single();if(pe)throw pe;profile.value=p
    if(p.password_set===false){passwordSetupRequired.value=true;sessionStorage.setItem('readerRoomPasswordSetup','true');loading.value=false;return}
    if(portal.value==='choice')portal.value=p.role==='admin'?'admin':p.role==='author'?'author':'reader'
    if(['admin','author'].includes(p.role)){await loadAuthorData();if(p.role==='admin')await Promise.all([loadAuthorInvitations(),loadPeople()])}else await loadReaderData()
  }catch(error){errorMessage.value=error.message||'The workspace could not be loaded.'}finally{loading.value=false}
}
async function loadAuthorInvitations(){
  const {data,error}=await supabase.from('author_invitations').select('*').order('invited_at',{ascending:false});if(error)throw error;authorInvitations.value=data||[]
}
async function loadPeople(){
  const {data,error}=await supabase.from('profiles').select('id,email,full_name,role,password_set,created_at').neq('role','admin').order('created_at',{ascending:false});if(error)throw error;people.value=data||[]
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

function handleFiles(e){
  const collator=new Intl.Collator(undefined,{numeric:true,sensitivity:'base'})
  const selected=Array.from(e.target.files||[])
  const invalid=selected.find(file=>!(/\.(docx|txt|pdf)$/i.test(file.name)))
  const oversized=selected.find(file=>file.size>20*1024*1024)
  if(invalid||oversized){e.target.value='';newBook.value.files=[];return flash(invalid?'Choose DOCX, TXT, or PDF files only.':`${oversized.name} is larger than 20 MB.`)}
  newBook.value.files=selected.sort((a,b)=>collator.compare(a.name,b.name))
  if(newBook.value.files.length===1&&!newBook.value.title)newBook.value.title=newBook.value.files[0].name.replace(/\.(docx|txt|pdf)$/i,'')
}
async function extractText(file){
  if(!file)return newBook.value.manuscriptText.trim()
  if(file.name.toLowerCase().endsWith('.txt'))return file.text()
  const arrayBuffer=await file.arrayBuffer()
  if(file.name.toLowerCase().endsWith('.pdf')){
    const pdfjs=await import('pdfjs-dist');pdfjs.GlobalWorkerOptions.workerSrc=pdfWorkerUrl
    const document=await pdfjs.getDocument({data:new Uint8Array(arrayBuffer)}).promise;const pages=[]
    for(let pageNumber=1;pageNumber<=document.numPages;pageNumber++){
      const page=await document.getPage(pageNumber);const content=await page.getTextContent()
      pages.push(content.items.map(item=>`${item.str}${item.hasEOL?'\n':' '}`).join('').trim())
    }
    return pages.join('\n\n').trim()
  }
  const mammoth=await import('mammoth/mammoth.browser');return (await mammoth.extractRawText({arrayBuffer})).value.trim()
}
function titleFromFilename(file,index){return file.name.replace(/\.(docx|txt|pdf)$/i,'').replace(/[_-]+/g,' ').replace(/\s+/g,' ').trim()||`Chapter ${index+1}`}
function splitChapters(text){
  const clean=text.replace(/\r\n/g,'\n').trim();const pattern=/^(chapter\s+(?:\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty)[^\n]*)$/gim;const matches=[...clean.matchAll(pattern)]
  if(!matches.length)return[{chapter_number:1,title:'Chapter 1',content:clean}]
  return matches.map((m,i)=>({chapter_number:i+1,title:m[0].trim(),content:clean.slice(m.index+m[0].length,matches[i+1]?.index??clean.length).trim()})).filter(c=>c.content)
}
function withReviewKeys(items){return items.map((chapter,index)=>({...chapter,chapter_number:index+1,_key:crypto.randomUUID()}))}
function renumberReviewChapters(){reviewChapters.value.forEach((chapter,index)=>chapter.chapter_number=index+1)}
function setChapterTextarea(element,key){if(element)chapterTextareas.set(key,element);else chapterTextareas.delete(key)}
function moveChapter(index,direction){
  const target=index+direction;if(target<0||target>=reviewChapters.value.length)return
  const next=[...reviewChapters.value];[next[index],next[target]]=[next[target],next[index]];reviewChapters.value=next;renumberReviewChapters()
}
function mergeChapterDown(index){
  if(index>=reviewChapters.value.length-1)return
  const next=reviewChapters.value[index+1];reviewChapters.value[index].content=[reviewChapters.value[index].content,next.content].filter(Boolean).join('\n\n')
  reviewChapters.value.splice(index+1,1);renumberReviewChapters()
}
function splitChapter(index){
  const chapter=reviewChapters.value[index],textarea=chapterTextareas.get(chapter._key),cursor=textarea?.selectionStart
  if(!Number.isInteger(cursor)||cursor<=0||cursor>=chapter.content.length)return flash('Place the cursor in the chapter content where the new chapter should begin.')
  const before=chapter.content.slice(0,cursor).trim(),after=chapter.content.slice(cursor).trim()
  if(!before||!after)return flash('Both chapters need content.')
  chapter.content=before;reviewChapters.value.splice(index+1,0,{_key:crypto.randomUUID(),chapter_number:index+2,title:`Chapter ${index+2}`,content:after});renumberReviewChapters()
}
function removeChapter(index){
  if(reviewChapters.value.length===1)return flash('A manuscript must contain at least one chapter.')
  reviewChapters.value.splice(index,1);renumberReviewChapters()
}
function closeChapterReview(){showChapterReview.value=false;reviewChapters.value=[];reviewBook.value=null;chapterTextareas.clear()}
function resetNewBook(){newBook.value={title:'',author_name:profile.value?.full_name||'Teejaye Deloach',genre:'',description:'',deadline:'',manuscriptText:'',files:[]}}
async function prepareNewBookReview(){
  if(!newBook.value.title.trim()&&newBook.value.files.length>1)return flash('Add the book title.')
  if(!newBook.value.title.trim()||(!newBook.value.files.length&&!newBook.value.manuscriptText.trim()))return flash('Add a title and manuscript file or text.')
  if(!newBook.value.genre)return flash('Choose a genre.')
  actionLoading.value=true
  try{
    let chapterRows
    if(newBook.value.files.length>1){
      const contents=await Promise.all(newBook.value.files.map(extractText))
      if(contents.some(content=>!content.trim()))throw new Error('One or more files contained no readable text. Scanned PDFs must be converted with OCR before uploading.')
      chapterRows=contents.map((content,index)=>({chapter_number:index+1,title:titleFromFilename(newBook.value.files[index],index),content}))
    }else{
      const text=await extractText(newBook.value.files[0]||null);if(!text.trim())throw new Error('No readable text was found. Scanned PDFs must be converted with OCR before uploading.');chapterRows=splitChapters(text)
    }
    reviewMode.value='create';reviewBook.value={title:newBook.value.title.trim(),author_name:newBook.value.author_name.trim()||profile.value.full_name||'Author',genre:newBook.value.genre,description:newBook.value.description.trim(),overall_deadline:newBook.value.deadline,status:'active'}
    reviewChapters.value=withReviewKeys(chapterRows);showNewBook.value=false;showChapterReview.value=true
  }catch(error){flash(error.message||'The manuscript could not be parsed.')}finally{actionLoading.value=false}
}
async function startEditBook(book){
  actionLoading.value=true
  try{
    const {data,error}=await supabase.from('chapters').select('*').eq('book_id',book.id).eq('version_number',book.current_version||1).order('chapter_number');if(error)throw error
    reviewMode.value='edit';reviewBook.value={...book,overall_deadline:book.overall_deadline||'',description:book.description||''};reviewChapters.value=withReviewKeys(data||[])
    if(!reviewChapters.value.length)reviewChapters.value=withReviewKeys([{chapter_number:1,title:'Chapter 1',content:''}])
    showChapterReview.value=true
  }catch(error){flash(error.message||'The book could not be opened for editing.')}finally{actionLoading.value=false}
}
function validateReview(){
  if(!reviewBook.value?.title?.trim()||!reviewBook.value?.author_name?.trim())return 'Add the book title and author name.'
  if(!reviewBook.value.genre)return 'Choose a genre.'
  if(!reviewChapters.value.length)return 'Add at least one chapter.'
  if(reviewChapters.value.some(chapter=>!chapter.title.trim()||!chapter.content.trim()))return 'Every chapter needs a title and content.'
  return ''
}
async function saveReviewedBook(){
  const validation=validateReview();if(validation)return flash(validation)
  actionLoading.value=true
  try{
    if(reviewMode.value==='create')await saveInitialBook()
    else{
      const chaptersPayload=reviewChapters.value.map(({title,content})=>({title:title.trim(),content:content.trim()}))
      const {data,error}=await supabase.rpc('save_book_revision',{p_book_id:reviewBook.value.id,p_title:reviewBook.value.title.trim(),p_author_name:reviewBook.value.author_name.trim(),p_genre:reviewBook.value.genre,p_description:reviewBook.value.description?.trim()||null,p_overall_deadline:reviewBook.value.overall_deadline||null,p_status:reviewBook.value.status,p_chapters:chaptersPayload});if(error)throw error
      const title=reviewBook.value.title;closeChapterReview();await loadAuthorData();flash(`${title} was saved as version ${data}.`)
    }
  }catch(error){
    const message=error.message||''
    flash(message.includes('row-level security policy for table "books"')?'Your author access needs repair. Run the latest supabase/add-book-editing.sql in Supabase, sign out, and sign back in.':message.includes('save_book_revision')||message.includes('create_book_project')||message.includes('Could not find the function')?'Run the latest supabase/add-book-editing.sql in Supabase, then try again.':message||'The book could not be saved.')
  }finally{actionLoading.value=false}
}
async function saveInitialBook(){
  const metadata=reviewBook.value
  const chaptersPayload=reviewChapters.value.map(({title,content})=>({title:title.trim(),content:content.trim()}))
  const {data:bookId,error}=await supabase.rpc('create_book_project',{p_title:metadata.title.trim(),p_author_name:metadata.author_name.trim(),p_genre:metadata.genre,p_description:metadata.description?.trim()||null,p_overall_deadline:metadata.overall_deadline||null,p_status:'active',p_chapters:chaptersPayload});if(error)throw error
  const paths=[]
  for(const [index,file] of newBook.value.files.entries()){
    const path=`${session.value.user.id}/${bookId}/v1-${String(index+1).padStart(3,'0')}-${Date.now()}-${file.name.replace(/[^a-zA-Z0-9._-]/g,'-')}`
    const upload=await supabase.storage.from('manuscripts').upload(path,file);if(upload.error)throw upload.error;paths.push(path)
  }
  const fileLabel=newBook.value.files.length>1?`${newBook.value.files.length} chapter files`:newBook.value.files[0]?.name||null
  if(paths.length){
    const bookUpdate=await supabase.from('books').update({manuscript_path:paths[0],manuscript_filename:fileLabel}).eq('id',bookId);if(bookUpdate.error)throw bookUpdate.error
    const versionUpdate=await supabase.from('manuscript_versions').update({storage_path:paths[0],filename:fileLabel}).eq('book_id',bookId).eq('version_number',1);if(versionUpdate.error)throw versionUpdate.error
  }
  const title=metadata.title;closeChapterReview();resetNewBook();await loadAuthorData();flash(`${title} is ready for readers.`)
}

function startInvite(bookId=''){newInvite.value={email:'',book_id:bookId||books.value[0]?.id||'',deadline:''};showInvite.value=true}
async function sendInvitationEmail(payload){
  const {data}=await supabase.auth.getSession();const token=data.session?.access_token
  if(!token)throw new Error('Your session expired. Sign in again and resend the invitation.')
  const response=await fetch('/api/send-invitation',{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${token}`},body:JSON.stringify(payload)})
  const result=await response.json().catch(()=>({}));if(!response.ok)throw new Error(result.error||'The invitation email could not be sent.')
}
async function inviteReader(){
  if(!newInvite.value.email||!newInvite.value.book_id)return;actionLoading.value=true
  const email=newInvite.value.email.trim().toLowerCase()
  const existing=invitations.value.find(i=>i.book_id===newInvite.value.book_id&&i.email.toLowerCase()===email)
  const payload={book_id:newInvite.value.book_id,email,individual_deadline:newInvite.value.deadline||null,status:existing?.reader_id?'accepted':'pending',revoked_at:null,accepted_at:existing?.reader_id?new Date().toISOString():null,completed_at:null}
  const result=existing?await supabase.from('reader_invitations').update(payload).eq('id',existing.id):await supabase.from('reader_invitations').insert(payload)
  const {error}=result
  if(error){actionLoading.value=false;return flash(error.message)}
  showInvite.value=false;await loadAuthorData()
  try{await sendInvitationEmail({type:'reader',email,book_id:newInvite.value.book_id});flash('Reader access created and invitation email sent.')}
  catch(mailError){flash(`Reader access was created, but email failed: ${mailError.message}`)}
  finally{actionLoading.value=false}
}
async function removeReader(i){
  const revoked=i.revoked_at||i.status==='revoked'
  if(!window.confirm(revoked?`Permanently remove ${i.email} from the reader list?`:`Remove ${i.email} from this manuscript? Their access and reading progress for this invitation will be removed.`))return
  const {error}=await supabase.from('reader_invitations').delete().eq('id',i.id)
  if(error)flash(error.message);else{await loadAuthorData();flash(revoked?'Revoked reader removed from the list.':'Reader removed. The reader spot is available now.')}
}
async function inviteAuthor(){
  const email=newAuthorEmail.value.trim().toLowerCase();if(!email)return
  actionLoading.value=true;const {error}=await supabase.rpc('invite_author',{author_email:email})
  if(error){actionLoading.value=false;return flash(error.message)}
  newAuthorEmail.value='';await loadAuthorInvitations()
  try{await sendInvitationEmail({type:'author',email});flash('Author access created and invitation email sent.')}
  catch(mailError){flash(`Author access was created, but email failed: ${mailError.message}`)}
  finally{actionLoading.value=false}
}
async function resendAuthorInvitation(invitation){actionLoading.value=true;try{await sendInvitationEmail({type:'author',email:invitation.email});flash('Author invitation email sent.')}catch(error){flash(error.message)}finally{actionLoading.value=false}}
async function revokeAuthor(invitation){
  actionLoading.value=true;const {error}=await supabase.rpc('revoke_author',{invitation_id:invitation.id});actionLoading.value=false
  if(error)flash(error.message);else{await loadAuthorInvitations();flash('Author access revoked.')}
}
async function removeRevokedAuthor(invitation){
  if(!invitation.revoked_at||!window.confirm(`Permanently remove ${invitation.email} from the author list?`))return
  actionLoading.value=true;const {error}=await supabase.from('author_invitations').delete().eq('id',invitation.id);actionLoading.value=false
  if(error)flash(error.message);else{await loadAuthorInvitations();flash('Revoked author removed from the list.')}
}

function generateTemporaryPassword(){
  const required=['ABCDEFGHJKLMNPQRSTUVWXYZ','abcdefghijkmnopqrstuvwxyz','23456789','!@#$%&*?'].map(set=>set[crypto.getRandomValues(new Uint32Array(1))[0]%set.length])
  const all='ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%&*?';while(required.length<14)required.push(all[crypto.getRandomValues(new Uint32Array(1))[0]%all.length])
  for(let index=required.length-1;index>0;index--){const swap=crypto.getRandomValues(new Uint32Array(1))[0]%(index+1);[required[index],required[swap]]=[required[swap],required[index]]}
  newPerson.value.temp_password=required.join('');showTempPassword.value=true
}
async function createPerson(){
  const person={...newPerson.value,email:newPerson.value.email.trim().toLowerCase(),full_name:newPerson.value.full_name.trim()}
  if(!person.full_name||!person.email)return flash('Add the person’s name and email address.')
  if(!temporaryPasswordIsValid.value)return flash('The temporary password must meet every password requirement.')
  actionLoading.value=true
  try{
    const {data}=await supabase.auth.getSession();const token=data.session?.access_token;if(!token)throw new Error('Your session expired. Sign in again.')
    const response=await fetch('/api/admin-create-user',{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${token}`},body:JSON.stringify(person)})
    const result=await response.json().catch(()=>({}));if(!response.ok)throw new Error(result.error||'The account could not be created.')
    createdAccount.value={email:person.email,role:person.role,password:person.temp_password}
    newPerson.value={full_name:'',email:'',role:'author',temp_password:'',book_id:''};showTempPassword.value=false
    await Promise.all([loadPeople(),loadAuthorData()]);flash(`${person.full_name} was added as a ${person.role}.`)
  }catch(error){flash(error.message||'The account could not be created.')}finally{actionLoading.value=false}
}
async function copyCreatedCredentials(){
  if(!createdAccount.value)return
  await navigator.clipboard.writeText(`The Reader Room\nEmail: ${createdAccount.value.email}\nTemporary password: ${createdAccount.value.password}\nPortal: ${window.location.origin}/${createdAccount.value.role}-login`);flash('Temporary login details copied.')
}

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
  const {data}=await supabase.auth.getSession();session.value=data.session;if(session.value&&!passwordSetupRequired.value)await loadWorkspace();else loading.value=false
  authSubscription=supabase.auth.onAuthStateChange(async(_,s)=>{session.value=s;if(s&&!passwordSetupRequired.value)await loadWorkspace()}).data.subscription
})
onBeforeUnmount(()=>{window.removeEventListener('keydown',blockAction);window.removeEventListener('contextmenu',blockContext);authSubscription?.unsubscribe()})
</script>

<template>
  <div v-if="loading" class="center-screen"><div class="loader"></div><strong>Opening The Reader Room…</strong></div>
  <div v-else-if="!isSupabaseConfigured" class="center-screen error-screen"><ShieldCheck :size="34"/><h1>Connection needed</h1><p>Add the Supabase project URL and publishable key to the Netlify environment.</p></div>

  <main v-else-if="!session" class="auth-page">
    <section class="auth-brand"><img class="auth-primary-logo" src="/assets/reader-room-logo-white.svg?v=3" alt="The Reader Room, where stories meet their first readers"/><p>A protected place for meaningful stories, trusted readers, and feedback that helps the work grow.</p><div class="auth-promise"><ShieldCheck/><span>Private manuscripts<small>Personalized access and accountable feedback</small></span></div></section>
    <section class="auth-card">
      <img class="auth-card-logo" src="/assets/reader-room-primary-logo.svg?v=2" alt="The Reader Room"/>
      <div v-if="portal==='choice'" class="portal-choice">
        <p class="eyebrow">THREE PORTALS, ONE CREATIVE COMMUNITY</p><h2>How are you entering?</h2><p class="portal-intro">Choose the portal that matches your role. Administrators, authors, and beta readers each have a separate, protected workspace.</p>
        <div class="portal-choice-grid">
          <button class="portal-option admin-portal" @click="selectPortal('admin')"><span class="portal-icon"><ShieldCheck/></span><span class="portal-copy"><small>ADMINISTRATOR PORTAL</small><strong>I’m an Administrator</strong><span>Manage authors, manuscripts, and reader access across The Reader Room.</span></span><span class="portal-action">Administrator sign in <ChevronRight/></span></button>
          <button class="portal-option author-portal" @click="selectPortal('author')"><span class="portal-icon"><BookOpen/></span><span class="portal-copy"><small>AUTHOR PORTAL</small><strong>I’m an Author</strong><span>Upload manuscripts, invite readers, and review feedback.</span></span><span class="portal-action">Author sign in <ChevronRight/></span></button>
          <button class="portal-option reader-portal" @click="selectPortal('reader')"><span class="portal-icon"><Users/></span><span class="portal-copy"><small>BETA READER PORTAL</small><strong>I’m a Beta Reader</strong><span>Open an invited manuscript, read securely, and leave feedback.</span></span><span class="portal-action">Reader sign in <ChevronRight/></span></button>
        </div>
        <p class="portal-help"><LockKeyhole :size="14"/> Access requires an approved account or invitation. Use the approved email address.</p>
      </div>
      <div v-else-if="authMode==='password'">
        <button class="text-button auth-back" @click="portalHome">← Choose another entrance</button><p class="eyebrow">{{portal==='admin'?'ADMINISTRATOR PORTAL':portal==='author'?'AUTHOR PORTAL':'READER PORTAL'}}</p><h2>{{portal==='admin'?'Manage The Reader Room.':portal==='author'?'Manage your work.':'Open your reading shelf.'}}</h2><p>Sign in with the email address approved for this portal and your secure password.</p><label>Email address<input v-model="authEmail" type="email" autocomplete="email" placeholder="you@example.com"/></label><label>Password<div class="password-input-wrap"><input v-model="authPassword" :type="showAuthPassword?'text':'password'" autocomplete="current-password" placeholder="Your password" @keyup.enter="signInWithPassword"/><button type="button" :aria-label="showAuthPassword?'Hide password':'Show password'" :title="showAuthPassword?'Hide password':'Show password'" @click="showAuthPassword=!showAuthPassword"><EyeOff v-if="showAuthPassword"/><Eye v-else/></button></div></label><button class="primary full" :disabled="actionLoading" @click="signInWithPassword">{{actionLoading?'Signing in…':'Sign in securely'}} <ChevronRight :size="17"/></button><button class="text-button setup-password-link" @click="setupPassword">First sign-in or forgot your password?</button>
      </div>
      <div v-else-if="!codeSent">
        <button class="text-button auth-back" @click="authMode='password';authError=''">← Return to password sign in</button><p class="eyebrow">VERIFY YOUR INVITATION</p><h2>Create or reset your password.</h2><p>Enter the exact email address approved for this portal. We’ll email a one-time verification code before you create a password.</p><label>Email address<input v-model="authEmail" type="email" autocomplete="email" placeholder="you@example.com" @keyup.enter="sendCode"/></label><button class="primary full" :disabled="actionLoading" @click="sendCode">{{actionLoading?'Checking…':'Email my verification code'}} <ChevronRight :size="17"/></button>
      </div>
      <div v-else>
        <button class="text-button auth-back" @click="codeSent=false;authCode=''">← Change email</button><p class="eyebrow">CHECK YOUR EMAIL</p><h2>Enter your code.</h2><p>We sent a code to <strong>{{authEmail}}</strong>.</p><label>Verification code<input v-model="authCode" class="code-input" inputmode="numeric" maxlength="8" placeholder="000000" @keyup.enter="verifyCode"/></label><button class="primary full" :disabled="actionLoading" @click="verifyCode">{{actionLoading?'Verifying…':'Verify my email'}}</button>
      </div>
      <p v-if="authError" class="form-error">{{authError}}</p><small v-if="portal!=='choice'" class="auth-terms">By continuing, you agree to respect manuscript confidentiality and the creative work shared here.</small>
    </section>
  </main>

  <main v-else-if="passwordSetupRequired" class="auth-page password-setup-page">
    <section class="auth-brand"><img class="auth-primary-logo" src="/assets/reader-room-logo-white.svg?v=3" alt="The Reader Room"/><p>Your account is verified. Create the password you will use for future visits.</p><div class="auth-promise"><LockKeyhole/><span>Secure account access<small>Your temporary password or verification code cannot be reused</small></span></div></section>
    <section class="auth-card password-card"><img class="auth-card-logo" src="/assets/reader-room-primary-logo.svg?v=2" alt="The Reader Room"/><p class="eyebrow">SECURE YOUR ACCOUNT</p><h2>Create your password.</h2><p>Use a unique password that you do not use on another website.</p><label>New password<div class="password-input-wrap"><input v-model="newPassword" :type="showNewPassword?'text':'password'" autocomplete="new-password" placeholder="At least 10 characters"/><button type="button" :aria-label="showNewPassword?'Hide new password':'Show new password'" :title="showNewPassword?'Hide password':'Show password'" @click="showNewPassword=!showNewPassword"><EyeOff v-if="showNewPassword"/><Eye v-else/></button></div></label><ul class="password-rules"><li :class="{met:passwordRules.length}"><Check/> At least 10 characters</li><li :class="{met:passwordRules.capital}"><Check/> One capital letter</li><li :class="{met:passwordRules.lowercase}"><Check/> One lowercase letter</li><li :class="{met:passwordRules.number}"><Check/> One number</li><li :class="{met:passwordRules.special}"><Check/> One special character</li></ul><label>Confirm password<div class="password-input-wrap"><input v-model="confirmPassword" :type="showConfirmPassword?'text':'password'" autocomplete="new-password" placeholder="Enter the same password" @keyup.enter="savePassword"/><button type="button" :aria-label="showConfirmPassword?'Hide confirmed password':'Show confirmed password'" :title="showConfirmPassword?'Hide password':'Show password'" @click="showConfirmPassword=!showConfirmPassword"><EyeOff v-if="showConfirmPassword"/><Eye v-else/></button></div></label><p v-if="confirmPassword&&newPassword!==confirmPassword" class="password-mismatch">The passwords do not match.</p><button class="primary full" :disabled="actionLoading||!passwordIsValid" @click="savePassword">{{actionLoading?'Saving password…':'Save password and enter'}}</button><p v-if="authError" class="form-error">{{authError}}</p><button class="text-button cancel-password" @click="signOut">Cancel and sign out</button></section>
  </main>

  <div v-else-if="wrongPortal" class="center-screen error-screen"><ShieldCheck :size="34"/><h1>Use the correct entrance</h1><p>This account is not approved for the selected portal.</p><button class="primary" @click="signOut">Return to sign in</button></div>
  <div v-else-if="errorMessage" class="center-screen error-screen"><ShieldCheck :size="34"/><h1>Setup is not finished</h1><p>{{errorMessage}}</p><p>Run the Reader Room database setup in Supabase, then try again.</p><button class="primary" @click="loadWorkspace">Try again</button></div>

  <div v-else-if="!isAuthor" class="reader-home">
    <header class="reader-home-header"><img class="dark-brand-logo header-brand-logo" src="/assets/reader-room-logo-white.svg?v=3" alt="The Reader Room"/><div><span>{{readerEmail}}</span><button class="secondary" @click="signOut"><LogOut :size="16"/> Sign out</button></div></header>
    <main class="reader-library"><p class="eyebrow">YOUR READING SHELF</p><h1>Welcome to The Reader Room.</h1><p>Your invited manuscripts appear here. Feedback from other readers is never shown to you.</p><section v-if="readerInvitations.length" class="reader-book-grid"><article v-for="invite in readerInvitations" :key="invite.id" class="reader-book"><div class="book-cover large holiday"><BookOpen/></div><div><span class="status" :class="invite.status">{{invite.status}}</span><h2>{{invite.books?.title}}</h2><p>{{invite.books?.author_name}}</p><small>Deadline: {{invite.individual_deadline||invite.books?.overall_deadline||'Set by author'}}</small><button class="primary" :disabled="invite.status==='revoked'" @click="openBook(invite.books,invite)">Continue reading <ChevronRight :size="16"/></button></div></article></section><section v-else class="panel empty-state"><Inbox :size="34"/><h2>No invitations yet</h2><p>Sign in with the exact email address the author invited.</p></section></main>
  </div>

  <div v-else class="app-shell">
    <aside class="sidebar" :class="{open:mobileNav}"><button class="mobile-close" @click="mobileNav=false"><X/></button><img class="dark-brand-logo sidebar-brand-logo" src="/assets/reader-room-logo-white.svg?v=3" alt="The Reader Room"/><nav><button v-for="item in nav" :key="item.id" :class="{active:activeView===item.id}" @click="changeView(item.id)"><component :is="item.icon" :size="19"/><span>{{item.label}}</span><span v-if="item.id==='feedback'&&newFeedback.length" class="nav-count">{{newFeedback.length}}</span></button></nav><div class="collective-card"><Sparkles :size="18"/><strong>Creative community</strong><p>A protected space centered on LGBTQ+ stories and the people who shape them.</p></div><div class="profile-chip"><div class="avatar plum">{{(profile?.full_name||'TR').slice(0,2).toUpperCase()}}</div><div><strong>{{profile?.full_name}}</strong><small>{{profile?.role}}</small></div><button class="bare-icon" @click="signOut"><LogOut :size="17"/></button></div></aside>
    <main><header class="topbar"><button class="menu-button" @click="mobileNav=true"><Menu/></button><div><p class="eyebrow">{{isAdmin?'ADMINISTRATOR PORTAL':'AUTHOR WORKSPACE'}}</p><h1>{{pageTitle}}</h1></div><div class="top-actions"><button class="icon-button"><Bell :size="19"/></button><button class="primary" @click="showNewBook=true"><Plus :size="18"/> New book</button></div></header>
      <section v-if="activeView==='dashboard'" class="content"><div class="welcome-row"><div><h2>Good to see you, {{profile?.full_name?.split(' ')[0]}}.</h2><p>{{newFeedback.length}} feedback notes are waiting for review.</p></div></div><div class="metric-grid"><article><span class="metric-icon violet"><BookOpen/></span><div><small>ACTIVE BOOKS</small><strong>{{activeBooks.length}}</strong><p>{{books.length}} total projects</p></div></article><article><span class="metric-icon teal"><Users/></span><div><small>ACTIVE READERS</small><strong>{{activeReaders.length}}</strong><p>Across your books</p></div></article><article><span class="metric-icon gold"><MessageSquare/></span><div><small>FEEDBACK</small><strong>{{feedback.length}}</strong><p>{{newFeedback.length}} need review</p></div></article><article><span class="metric-icon rose"><Gauge/></span><div><small>READER LIMIT</small><strong>10</strong><p>Per book</p></div></article></div><section class="panel projects-panel"><div class="panel-head"><div><p class="eyebrow">MANUSCRIPTS</p><h3>Your books</h3></div><button class="text-button" @click="changeView('books')">View all <ChevronRight :size="16"/></button></div><div v-if="!books.length" class="empty-state compact"><BookOpen/><h3>No books yet</h3><p>Upload your first manuscript to begin.</p><button class="primary" @click="showNewBook=true">Add manuscript</button></div><div v-for="book in books.slice(0,4)" :key="book.id" class="book-row"><div class="book-cover holiday"><BookOpen :size="18"/></div><div class="book-info"><h4>{{book.title}}</h4><p>{{book.genre||'Genre not set'}} · {{book.status}}</p></div><div class="book-stat"><strong>{{invitations.filter(i=>i.book_id===book.id&&!i.revoked_at).length}}/10</strong><small>readers</small></div><button class="secondary small-button" @click="openBook(book)">Preview</button></div></section></section>
      <section v-else-if="activeView==='books'" class="content"><div class="welcome-row"><div><h2>Manuscript projects</h2><p>Upload DOCX, TXT, or PDF files, or paste your manuscript text.</p></div><button class="primary" @click="showNewBook=true"><Plus :size="18"/> Add book</button></div><div v-if="books.length" class="book-card-grid"><article v-for="book in books" :key="book.id" class="panel book-card"><div class="book-card-top"><div class="book-cover large holiday"><BookOpen/></div><span class="status" :class="book.status">{{book.status}}</span></div><p class="eyebrow">{{book.genre||'MANUSCRIPT'}}</p><h3>{{book.title}}</h3><p class="book-byline">{{book.author_name}}</p><div class="card-footer"><span><Users :size="16"/> {{invitations.filter(i=>i.book_id===book.id&&!i.revoked_at).length}}/10</span><button class="secondary" @click="startInvite(book.id)"><Send :size="15"/> Invite</button><button class="secondary" @click="startEditBook(book)"><Pencil :size="15"/> Edit</button><button class="primary" @click="openBook(book)">Open</button></div></article></div><div v-else class="panel empty-state"><BookOpen/><h2>Your shelf is empty</h2><p>Create your first project with a DOCX, TXT, or PDF file, or pasted manuscript text.</p><button class="primary" @click="showNewBook=true">Add your first book</button></div></section>
      <section v-else-if="activeView==='authors'&&isAdmin" class="content"><div class="welcome-row"><div><h2>People and access</h2><p>Create author or reader accounts directly, or keep using email invitations.</p></div></div><section class="panel direct-account-panel"><div class="panel-head"><div><p class="eyebrow">DIRECT ACCOUNT</p><h3>Add a person without an invitation</h3></div></div><form class="direct-account-form" @submit.prevent="createPerson"><label>Full name<input v-model="newPerson.full_name" autocomplete="name" placeholder="Full name" required/></label><label>Email address<input v-model="newPerson.email" type="email" autocomplete="email" placeholder="person@example.com" required/></label><label>Role<select v-model="newPerson.role" @change="newPerson.role==='author'&&(newPerson.book_id='')"><option value="author">Author</option><option value="reader">Reader</option></select></label><label v-if="newPerson.role==='reader'">Book access (optional)<select v-model="newPerson.book_id"><option value="">No book yet</option><option v-for="book in books" :key="book.id" :value="book.id">{{book.title}}</option></select></label><label class="temporary-password-field">Temporary password<div class="password-input-wrap"><input v-model="newPerson.temp_password" :type="showTempPassword?'text':'password'" autocomplete="new-password" placeholder="At least 10 characters" required/><button type="button" :aria-label="showTempPassword?'Hide temporary password':'Show temporary password'" @click="showTempPassword=!showTempPassword"><EyeOff v-if="showTempPassword"/><Eye v-else/></button></div><small>Use 10+ characters with uppercase, lowercase, a number, and a symbol.</small></label><div class="direct-account-actions"><button type="button" class="secondary" @click="generateTemporaryPassword">Generate password</button><button class="primary" :disabled="actionLoading||!temporaryPasswordIsValid">{{actionLoading?'Creating account…':'Create account'}}</button></div></form><div v-if="createdAccount" class="credentials-card"><div><strong>Temporary login details</strong><small>Copy these now. The password is shown only in this browser until you leave or create another account.</small></div><dl><div><dt>Email</dt><dd>{{createdAccount.email}}</dd></div><div><dt>Role</dt><dd>{{createdAccount.role}}</dd></div><div><dt>Temporary password</dt><dd><code>{{createdAccount.password}}</code></dd></div></dl><button class="secondary" @click="copyCreatedCredentials">Copy login details</button></div></section><section class="panel people-directory"><div class="panel-head"><div><p class="eyebrow">CURRENT ACCOUNTS</p><h3>Authors and readers</h3></div></div><div class="people-directory-head"><span>PERSON</span><span>ROLE</span><span>PASSWORD</span></div><template v-if="people.length"><div v-for="person in people" :key="person.id" class="people-directory-row"><div class="reader-cell"><span class="avatar">{{(person.full_name||person.email).slice(0,2).toUpperCase()}}</span><div><strong>{{person.full_name||person.email}}</strong><small>{{person.email}}</small></div></div><span class="status" :class="person.role">{{person.role}}</span><small>{{person.password_set?'Password active':'Temporary password'}}</small></div></template><div v-else class="empty-state compact"><Users/><h3>No accounts yet</h3></div></section><section class="panel author-directory"><div class="panel-head"><div><p class="eyebrow">EMAIL INVITATIONS</p><h3>Invite an author instead</h3></div></div><form class="author-invite-form" @submit.prevent="inviteAuthor"><label>Author email address<input v-model="newAuthorEmail" type="email" placeholder="author@example.com" required/></label><button class="primary" :disabled="actionLoading"><Send :size="17"/> {{actionLoading?'Sending invitation…':'Invite author'}}</button></form><div class="author-directory-head"><span>AUTHOR</span><span>STATUS</span><span>ACCESS</span></div><template v-if="authorInvitations.length"><div v-for="invite in authorInvitations" :key="invite.id" class="author-directory-row"><div class="reader-cell"><span class="avatar">{{invite.email.slice(0,2).toUpperCase()}}</span><div><strong>{{invite.email}}</strong><small>{{invite.accepted_at?'Account connected':'Waiting for first sign-in'}}</small></div></div><span class="status" :class="invite.status">{{invite.status}}</span><div class="author-actions"><button v-if="!invite.revoked_at" class="text-button" :disabled="actionLoading" @click="resendAuthorInvitation(invite)">Resend email</button><button v-if="!invite.revoked_at" class="danger-link" :disabled="actionLoading" @click="revokeAuthor(invite)">Remove</button><template v-else><button class="text-button" :disabled="actionLoading" @click="newAuthorEmail=invite.email;inviteAuthor()">Restore access</button><button class="danger-link" :disabled="actionLoading" @click="removeRevokedAuthor(invite)">Remove from list</button></template></div></div></template><div v-else class="empty-state compact"><Users/><h3>No author invitations</h3><p>Directly created authors do not need an invitation and appear in Current accounts.</p></div></section></section>
      <section v-else-if="activeView==='readers'" class="content"><div class="welcome-row"><div><h2>Reader directory</h2><p>{{isAdmin?'Manage reader access across every author and manuscript.':'Manage access separately for each of your manuscripts.'}}</p></div><button class="primary" :disabled="!books.length" @click="startInvite()"><Send :size="18"/> Invite reader</button></div><section class="panel data-panel"><div v-if="!invitations.length" class="empty-state"><Users/><h2>No readers invited</h2></div><template v-else><div class="reader-table-head"><span>READER</span><span>BOOK</span><span>STATUS</span><span>DEADLINE</span><span></span></div><div v-for="invite in invitations" :key="invite.id" class="reader-row"><div class="reader-cell"><span class="avatar">{{invite.email.slice(0,2).toUpperCase()}}</span><div><strong>{{invite.email}}</strong><small>{{invite.reader_id?'Account connected':'Waiting for sign-in'}}</small></div></div><span>{{books.find(b=>b.id===invite.book_id)?.title}}</span><span class="status" :class="invite.status">{{invite.status}}</span><small>{{invite.individual_deadline||'No date'}}</small><button class="danger-link" @click="removeReader(invite)">{{invite.revoked_at||invite.status==='revoked'?'Remove from list':'Remove'}}</button></div></template></section></section>
      <section v-else-if="activeView==='feedback'" class="content"><div class="welcome-row"><div><h2>Feedback inbox</h2><p>Every note is tied to the reader who submitted it.</p></div></div><div v-if="feedback.length" class="feedback-list"><article v-for="item in feedback" :key="item.id" class="panel feedback-card"><div class="feedback-meta"><div class="reader-cell"><span class="avatar">{{(item.profiles?.full_name||item.profiles?.email||'R').slice(0,2).toUpperCase()}}</span><div><strong>{{item.profiles?.full_name||item.profiles?.email}}</strong><small>{{item.books?.title}} · {{item.chapters?.title}}</small></div></div><small>{{new Date(item.created_at).toLocaleDateString()}}</small></div><blockquote>“{{item.quoted_text}}”</blockquote><p>{{item.comment_text}}</p><div class="feedback-actions"><select :value="item.status" @change="updateStatus(item,$event.target.value)"><option v-for="s in ['new','consider','revise','accepted','dismissed']" :key="s" :value="s">{{s}}</option></select></div></article></div><div v-else class="panel empty-state"><MessageSquare/><h2>No feedback yet</h2><p>Reader comments will appear here.</p></div></section>
      <section v-else class="content"><div class="welcome-row"><div><h2>{{isAdmin?'Administrator settings':'Workspace settings'}}</h2><p>{{isAdmin?'Platform security and owner information.':'Your security controls apply to every reading session.'}}</p></div></div><div class="settings-grid"><section class="panel settings-card"><h3>Manuscript protection</h3><div class="setting-confirm"><Check/> Author and reader watermark</div><div class="setting-confirm"><Check/> Copying and printing blocked</div><div class="setting-confirm"><Check/> Confidentiality agreement required</div></section><section class="panel settings-card"><h3>Owner account</h3><p>{{OWNER_EMAIL}}</p><p class="muted-copy">Administrators can create author and reader accounts directly or grant access by email invitation.</p></section></div></section>
    </main>
  </div>

  <div v-if="showNewBook" class="modal-backdrop" @click.self="showNewBook=false"><section class="modal"><button class="modal-close" @click="showNewBook=false"><X/></button><p class="eyebrow">NEW PROJECT</p><h2>Add your manuscript.</h2><p>Choose one complete manuscript file for automatic chapter detection, or select multiple files with one chapter in each file.</p><label>Book title<input v-model="newBook.title" placeholder="Working title"/></label><div class="form-grid"><label>Author name<input v-model="newBook.author_name"/></label><label>Genre<select v-model="newBook.genre"><option disabled value="">Choose a genre</option><optgroup v-for="group in genreGroups" :key="group.label" :label="group.label"><option v-for="genre in group.options" :key="genre" :value="genre">{{genre}}</option></optgroup></select></label></div><label>Description<textarea v-model="newBook.description" rows="3" placeholder="A short description for readers"></textarea></label><label>Overall deadline<input v-model="newBook.deadline" type="date"/></label><label class="file-drop"><Upload/><strong>{{newBook.files.length?newBook.files.length===1?newBook.files[0].name:`${newBook.files.length} chapter files selected`:'Choose one manuscript or multiple chapter files'}}</strong><small>DOCX, TXT, or PDF · maximum 20 MB per file</small><input type="file" accept=".docx,.txt,.pdf,application/pdf" multiple @change="handleFiles"/></label><div v-if="newBook.files.length>1" class="selected-files"><strong>Chapter order</strong><ol><li v-for="file in newBook.files" :key="file.name">{{file.name}}</li></ol><small>Files are sorted by filename. Number them 01, 02, 03, and so on.</small></div><div class="or"><span>OR PASTE ONE COMPLETE MANUSCRIPT</span></div><label>Manuscript text<textarea v-model="newBook.manuscriptText" rows="7" placeholder="Chapter 1&#10;&#10;Paste manuscript text here…"></textarea></label><button class="primary full" :disabled="actionLoading" @click="prepareNewBookReview">{{actionLoading?'Parsing manuscript…':'Review detected chapters'}}</button></section></div>
  <div v-if="showChapterReview" class="modal-backdrop chapter-review-backdrop"><section class="modal chapter-review-modal"><button class="modal-close" @click="closeChapterReview"><X/></button><p class="eyebrow">{{reviewMode==='create'?'CHAPTER REVIEW':'EDIT MANUSCRIPT'}}</p><h2>{{reviewMode==='create'?'Review before saving.':'Edit book details and chapters.'}}</h2><p>{{reviewMode==='create'?'Correct the detected chapters now. Nothing is saved until you approve this screen.':'Saving creates a new manuscript version. Existing feedback and reading records stay attached to the earlier chapter records.'}}</p><div class="review-metadata"><label>Book title<input v-model="reviewBook.title"/></label><label>Author name<input v-model="reviewBook.author_name"/></label><label>Genre<select v-model="reviewBook.genre"><option disabled value="">Choose a genre</option><optgroup v-for="group in genreGroups" :key="group.label" :label="group.label"><option v-for="genre in group.options" :key="genre" :value="genre">{{genre}}</option></optgroup></select></label><label>Deadline<input v-model="reviewBook.overall_deadline" type="date"/></label><label v-if="reviewMode==='edit'">Status<select v-model="reviewBook.status"><option v-for="status in statusOptions" :key="status" :value="status">{{status}}</option></select></label><label class="description-field">Description<textarea v-model="reviewBook.description" rows="3"></textarea></label></div><div class="chapter-review-heading"><div><strong>Chapters</strong><small>Rename, reorder, merge, remove, or place the cursor in content and split.</small></div><span>{{reviewChapters.length}} total</span></div><div class="chapter-editor-list"><article v-for="(chapter,index) in reviewChapters" :key="chapter._key" class="chapter-editor"><div class="chapter-editor-head"><span>{{index+1}}</span><input v-model="chapter.title" :aria-label="`Chapter ${index+1} title`"/><div class="chapter-actions"><button type="button" :disabled="index===0" title="Move up" @click="moveChapter(index,-1)"><ArrowUp/></button><button type="button" :disabled="index===reviewChapters.length-1" title="Move down" @click="moveChapter(index,1)"><ArrowDown/></button><button type="button" title="Split at cursor" @click="splitChapter(index)"><Scissors/></button><button type="button" :disabled="index===reviewChapters.length-1" title="Merge with next chapter" @click="mergeChapterDown(index)">Merge</button><button type="button" title="Remove chapter" @click="removeChapter(index)"><Trash2/></button></div></div><textarea :ref="element=>setChapterTextarea(element,chapter._key)" v-model="chapter.content" rows="10" :aria-label="`${chapter.title} content`"></textarea></article></div><div class="review-footer"><button class="secondary" :disabled="actionLoading" @click="closeChapterReview">Cancel</button><button class="primary" :disabled="actionLoading" @click="saveReviewedBook">{{actionLoading?'Saving…':reviewMode==='create'?'Save manuscript project':'Save as new version'}}</button></div></section></div>
  <div v-if="showInvite" class="modal-backdrop" @click.self="showInvite=false"><section class="modal compact"><button class="modal-close" @click="showInvite=false"><X/></button><p class="eyebrow">READER ACCESS</p><h2>Invite a trusted reader.</h2><p>Use the exact email address the reader will use to sign in.</p><label>Reader email<input v-model="newInvite.email" type="email" placeholder="reader@example.com"/></label><label>Book<select v-model="newInvite.book_id"><option disabled value="">Choose a book</option><option v-for="book in books" :key="book.id" :value="book.id">{{book.title}}</option></select></label><label>Individual deadline<input v-model="newInvite.deadline" type="date"/></label><button class="primary full" :disabled="actionLoading" @click="inviteReader">{{actionLoading?'Creating access…':'Create reader access'}}</button></section></div>
  <div v-if="showAgreement" class="modal-backdrop highest"><section class="modal agreement-modal"><ShieldCheck :size="34"/><p class="eyebrow">CONFIDENTIALITY AGREEMENT</p><h2>Protect the work in this room.</h2><p>By opening this manuscript, you agree not to copy, download, print, distribute, train an AI system on, or publicly discuss any part of it. Access is personal and may be revoked by the author.</p><button class="primary full" @click="acceptAgreement">I agree and will protect this manuscript</button><button class="text-button cancel-agreement" @click="showAgreement=false;selectedBook=null">Decline and leave</button></section></div>
  <div v-if="showReader" class="reader-overlay"><header class="reader-header"><button class="reader-back" @click="showReader=false"><ChevronLeft :size="18"/> Exit reader</button><div><strong>{{selectedBook?.title}}</strong><small>{{selectedChapter?.title||'No chapters'}}</small></div><div class="reader-tools"><span><LockKeyhole :size="15"/> Protected session</span></div></header><div class="reader-progress"><i :style="{width:chapters.length?`${((chapters.findIndex(c=>c.id===selectedChapter?.id)+1)/chapters.length)*100}%`:'0%'}"></i></div><main class="manuscript-wrap"><aside class="chapter-rail"><p class="eyebrow">CONTENTS</p><button v-for="chapter in chapters" :key="chapter.id" :class="{active:chapter.id===selectedChapter?.id}" @click="selectedChapter=chapter"><span>{{chapter.chapter_number}}</span><div><strong>{{chapter.title}}</strong></div></button></aside><article class="manuscript"><div class="watermarks"><span v-for="n in 12" :key="n">{{selectedBook?.author_name?.toUpperCase()}} · {{readerEmail}}</span></div><template v-if="selectedChapter"><p class="chapter-number">CHAPTER {{selectedChapter.chapter_number}}</p><h1>{{selectedChapter.title}}</h1><p v-if="!isAuthor" class="reader-instruction"><MessageSquare :size="15"/> Click any sentence to comment.</p><div class="prose"><button v-for="(sentence,index) in chapterSentences" :key="index" @click="openSentence(sentence,index)">{{sentence}} </button></div><div v-if="!isAuthor" class="chapter-end"><Check/><h3>Reached the end?</h3><button class="primary" @click="completeChapter">Complete chapter</button></div></template><div v-else class="empty-state"><FileText/><h2>No chapters found</h2></div></article></main><div v-if="showNotice" class="protection-notice"><ShieldCheck/><div><strong>This manuscript is protected.</strong><span>Copying, printing, and screenshots are not permitted.</span></div></div></div>
  <div v-if="showComment" class="modal-backdrop highest" @click.self="showComment=false"><section class="modal compact"><button class="modal-close" @click="showComment=false"><X/></button><p class="eyebrow">INLINE COMMENT</p><blockquote>“{{selectedSentence}}”</blockquote><label>Your note<textarea v-model="commentText" autofocus></textarea></label><button class="primary full" :disabled="actionLoading" @click="submitComment">Save comment</button></section></div>
  <Transition name="toast"><div v-if="toast" class="toast"><Check :size="17"/>{{toast}}</div></Transition>
</template>
