const messagesNode = document.querySelector('#messages');
const emptyNode = document.querySelector('#empty');
const conversationNode = document.querySelector('.conversation');
const transcriptHeader = document.querySelector('.transcript-header');
const statusNode = document.querySelector('#connection-status');
const countNode = document.querySelector('#message-count');
const form = document.querySelector('#composer');
const recipient = document.querySelector('#recipient');
const text = document.querySelector('#text');
const sendButton = document.querySelector('#send');
let lastSignature = '';

const dayFormat = new Intl.DateTimeFormat('fr-FR', {
  weekday: 'long', day: '2-digit', month: 'long', year: 'numeric'
});

const timeFormat = new Intl.DateTimeFormat('fr-FR', {
  hour: '2-digit', minute: '2-digit', second: '2-digit'
});

function parseDate(value) {
  const date = new Date(value);
  return Number.isNaN(date.valueOf()) ? null : date;
}

function dayKey(value) {
  const date = parseDate(value);
  return date ? `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}` : '';
}

function dateDivider(value) {
  const date = parseDate(value);
  const divider = document.createElement('div');
  divider.className = 'day-break';
  divider.textContent = date ? dayFormat.format(date) : 'DATE INCONNUE';
  return divider;
}

function dispatch(message) {
  const sender = ['Alice', 'Bob', 'Nathan'].includes(message.from) ? message.from : 'Nathan';
  const row = document.createElement('article');
  row.className = `dispatch ${sender.toLowerCase()}`;

  const time = document.createElement('time');
  const date = parseDate(message.created_at_utc);
  time.dateTime = message.created_at_utc || '';
  time.textContent = date ? timeFormat.format(date) : '--:--:--';

  const address = document.createElement('div');
  address.className = 'address';
  const author = document.createElement('strong');
  author.textContent = sender.toUpperCase();
  const route = document.createElement('span');
  route.textContent = `POUR ${String(message.to).toUpperCase()}`;
  address.append(author, route);

  const copy = document.createElement('p');
  copy.textContent = message.text;
  row.append(time, address, copy);
  return row;
}

function render(messages) {
  const signature = messages.map(message => message.id).join('|');
  if (signature === lastSignature) return;

  const followTail = conversationNode.scrollHeight - conversationNode.scrollTop - conversationNode.clientHeight < 80;
  lastSignature = signature;
  messagesNode.replaceChildren();
  emptyNode.hidden = messages.length > 0;
  countNode.textContent = String(messages.length).padStart(4, '0');

  let previousDay = null;
  for (const message of messages) {
    const currentDay = dayKey(message.created_at_utc);
    if (currentDay !== previousDay) {
      messagesNode.append(dateDivider(message.created_at_utc));
      previousDay = currentDay;
    }
    messagesNode.append(dispatch(message));
  }

  if (followTail || messages.length === 1) {
    conversationNode.scrollTop = conversationNode.scrollHeight;
  }
}

function setConnection(online) {
  transcriptHeader.classList.toggle('offline', !online);
  statusNode.textContent = online ? 'LIGNE LOCALE' : 'LIGNE COUPEE';
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
  text.style.height = `${Math.min(text.scrollHeight, 110)}px`;
});

refresh();
setInterval(refresh, 1250);
