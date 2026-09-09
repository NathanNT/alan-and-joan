const messagesNode = document.querySelector('#messages');
const emptyNode = document.querySelector('#empty');
const conversationNode = document.querySelector('.conversation');
const statusBar = document.querySelector('.correspondence-bar');
const statusNode = document.querySelector('#connection-status');
const countNode = document.querySelector('#message-count');
const form = document.querySelector('#composer');
const recipient = document.querySelector('#recipient');
const text = document.querySelector('#text');
const sendButton = document.querySelector('#send');
let lastSignature = '';

const dateFormatter = new Intl.DateTimeFormat('fr-FR', {
  weekday: 'long', day: '2-digit', month: 'long'
});

const timeFormatter = new Intl.DateTimeFormat('fr-FR', {
  hour: '2-digit', minute: '2-digit'
});

function toDate(value) {
  const date = new Date(value);
  return Number.isNaN(date.valueOf()) ? null : date;
}

function dayKey(value) {
  const date = toDate(value);
  return date ? `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}` : '';
}

function makeDateDivider(value) {
  const date = toDate(value);
  const divider = document.createElement('div');
  divider.className = 'date-divider';
  divider.textContent = date ? dateFormatter.format(date) : 'Date inconnue';
  return divider;
}

function makeMessage(message) {
  const authorName = ['Alice', 'Bob', 'Nathan'].includes(message.from) ? message.from : 'Nathan';
  const article = document.createElement('article');
  article.className = `message ${authorName.toLowerCase()}`;

  if (authorName !== 'Nathan') {
    const avatar = document.createElement('div');
    avatar.className = 'message-avatar';
    avatar.textContent = authorName.charAt(0);
    article.append(avatar);
  }

  const letter = document.createElement('div');
  letter.className = 'letter';
  const meta = document.createElement('div');
  meta.className = 'meta';
  const author = document.createElement('strong');
  author.textContent = authorName;
  const route = document.createElement('span');
  const date = toDate(message.created_at_utc);
  route.textContent = `pour ${message.to} / ${date ? timeFormatter.format(date) : '--:--'}`;
  const bubble = document.createElement('p');
  bubble.className = 'bubble';
  bubble.textContent = message.text;
  meta.append(author, route);
  letter.append(meta, bubble);
  article.append(letter);
  return article;
}

function render(messages) {
  const signature = messages.map(message => message.id).join('|');
  if (signature === lastSignature) return;

  const wasNearBottom = conversationNode.scrollHeight - conversationNode.scrollTop - conversationNode.clientHeight < 100;
  lastSignature = signature;
  messagesNode.replaceChildren();
  emptyNode.hidden = messages.length > 0;
  countNode.textContent = `${messages.length} ${messages.length === 1 ? 'lettre' : 'lettres'}`;

  let previousDay = null;
  for (const message of messages) {
    const currentDay = dayKey(message.created_at_utc);
    if (currentDay !== previousDay) {
      messagesNode.append(makeDateDivider(message.created_at_utc));
      previousDay = currentDay;
    }
    messagesNode.append(makeMessage(message));
  }

  if (wasNearBottom || messages.length === 1) {
    conversationNode.scrollTop = conversationNode.scrollHeight;
  }
}

function setConnection(ok) {
  statusBar.classList.toggle('offline', !ok);
  statusNode.textContent = ok ? 'Liaison locale' : 'Liaison interrompue';
}

async function refresh() {
  try {
    const response = await fetch('/api/messages', { cache: 'no-store' });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    render(await response.json());
    setConnection(true);
  } catch (_) {
    setConnection(false);
  }
}

async function sendMessage() {
  const value = text.value.trim();
  if (!value || sendButton.disabled) return;
  sendButton.disabled = true;
  try {
    const response = await fetch('/api/messages', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: 'Nathan', to: recipient.value, text: value })
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    text.value = '';
    text.style.height = '';
    await refresh();
  } finally {
    sendButton.disabled = false;
    text.focus();
  }
}

form.addEventListener('submit', async event => {
  event.preventDefault();
  await sendMessage();
});

text.addEventListener('keydown', async event => {
  if (event.ctrlKey && event.key === 'Enter') {
    event.preventDefault();
    await sendMessage();
  }
});

text.addEventListener('input', () => {
  text.style.height = 'auto';
  text.style.height = `${Math.min(text.scrollHeight, 130)}px`;
});

refresh();
setInterval(refresh, 1250);
