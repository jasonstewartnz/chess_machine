const API_BASE = 'http://localhost:8080';

const PIECE_IMAGES = {
  'white-king': 'https://upload.wikimedia.org/wikipedia/commons/4/42/Chess_klt45.svg',
  'white-queen': 'https://upload.wikimedia.org/wikipedia/commons/1/15/Chess_qlt45.svg',
  'white-rook': 'https://upload.wikimedia.org/wikipedia/commons/7/72/Chess_rlt45.svg',
  'white-bishop': 'https://upload.wikimedia.org/wikipedia/commons/b/b1/Chess_blt45.svg',
  'white-knight': 'https://upload.wikimedia.org/wikipedia/commons/7/70/Chess_nlt45.svg',
  'white-pawn': 'https://upload.wikimedia.org/wikipedia/commons/4/45/Chess_plt45.svg',
  'black-king': 'https://upload.wikimedia.org/wikipedia/commons/f/f0/Chess_kdt45.svg',
  'black-queen': 'https://upload.wikimedia.org/wikipedia/commons/4/47/Chess_qdt45.svg',
  'black-rook': 'https://upload.wikimedia.org/wikipedia/commons/f/ff/Chess_rdt45.svg',
  'black-bishop': 'https://upload.wikimedia.org/wikipedia/commons/9/98/Chess_bdt45.svg',
  'black-knight': 'https://upload.wikimedia.org/wikipedia/commons/e/ef/Chess_ndt45.svg',
  'black-pawn': 'https://upload.wikimedia.org/wikipedia/commons/c/c7/Chess_pdt45.svg',
};

const PIECE_VALUES = { 'pawn': 1, 'knight': 3, 'bishop': 3, 'rook': 5, 'queen': 9, 'king': 0 };
const INITIAL_COUNTS = {
  'white-pawn': 8, 'white-knight': 2, 'white-bishop': 2, 'white-rook': 2, 'white-queen': 1,
  'black-pawn': 8, 'black-knight': 2, 'black-bishop': 2, 'black-rook': 2, 'black-queen': 1
};
const EMOJIS = {
  'white-pawn': '♙', 'white-knight': '♘', 'white-bishop': '♗', 'white-rook': '♖', 'white-queen': '♕',
  'black-pawn': '♟', 'black-knight': '♞', 'black-bishop': '♝', 'black-rook': '♜', 'black-queen': '♛'
};

let gameState = null;
let selectedSquare = null;
let legalMoves = [];

const boardEl = document.getElementById('chessboard');
const statusEl = document.getElementById('status-indicator');
const resetBtn = document.getElementById('reset-btn');
const undoBtn = document.getElementById('undo-btn');
const whiteScoreEl = document.getElementById('white-score');
const blackScoreEl = document.getElementById('black-score');
const modeBtn = document.getElementById('mode-btn');
const whitePalette = document.getElementById('white-palette');
const blackPalette = document.getElementById('black-palette');
const playerInfos = document.querySelectorAll('.player-info');

// Show/hide explore UI elements
function applyMode(mode) {
  const explore = mode === 'explore';
  // palettes
  whitePalette.style.display = explore ? 'flex' : 'none';
  blackPalette.style.display = explore ? 'flex' : 'none';
  // hide scores in explore mode
  playerInfos.forEach(info => {
    const score = info.querySelector('.score-display');
    if (score) score.style.display = explore ? 'none' : 'inline';
  });
}

// Toggle mode on button click
modeBtn.addEventListener('click', async () => {
  const newMode = modeBtn.textContent.trim().toLowerCase() === 'game mode' ? 'explore' : 'game';
  await fetch(`${API_BASE}/set-mode?mode=${newMode}`, {method: 'POST'});
  // update button label
  modeBtn.textContent = newMode === 'game' ? 'Game Mode' : 'Explore Mode';
  applyMode(newMode);
  fetchState();
});

async function fetchState() {
  try {
    const res = await fetch(`${API_BASE}/state`);
    gameState = await res.json();
    renderBoard();
    updateStatus();
  } catch (err) {
    console.error('Failed to fetch state', err);
    statusEl.textContent = 'Server offline';
  }
}

async function fetchLegalMoves(sq) {
  try {
    const res = await fetch(`${API_BASE}/legal-moves?sq=${sq}`);
    const data = await res.json();
    legalMoves = data.moves || [];
    renderBoard();
  } catch (err) {
    console.error(err);
  }
}

async function makeMove(from, to) {
  try {
    const res = await fetch(`${API_BASE}/move`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: `from=${from}&to=${to}`
    });
    const data = await res.json();
    if (data.success) {
      gameState = data.state;
      selectedSquare = null;
      legalMoves = [];
      renderBoard();
      updateStatus();
    }
  } catch (err) {
    console.error(err);
  }
}

async function resetGame() {
  try {
    const res = await fetch(`${API_BASE}/reset`, { method: 'POST' });
    gameState = await res.json();
    selectedSquare = null;
    legalMoves = [];
    renderBoard();
    updateStatus();
  } catch (err) {
    console.error(err);
  }
}

async function undoGame() {
  try {
    const res = await fetch(`${API_BASE}/undo`, { method: 'POST' });
    const data = await res.json();
    if (data.success) {
      gameState = data.state;
      selectedSquare = null;
      legalMoves = [];
      renderBoard();
      updateStatus();
    }
  } catch (err) {
    console.error(err);
  }
}

function updateStatus() {
  if (!gameState) return;
  const status = gameState.status || 'active';
  const color = gameState.activeColor === 'white' ? 'White' : 'Black';
  
  if (status === 'checkmate') {
    statusEl.innerHTML = `<strong style="color: #ff4757">Checkmate! ${color === 'White' ? 'Black' : 'White'} wins!</strong>`;
  } else if (status === 'stalemate') {
    statusEl.innerHTML = `<strong>Stalemate! Draw.</strong>`;
  } else if (status === 'check') {
    statusEl.innerHTML = `${color} to move <strong style="color: #ff4757">(Check!)</strong>`;
  } else {
    statusEl.textContent = `${color} to move`;
  }
  
  if (gameState.material) {
    let wScore = 0;
    let bScore = 0;
    let whiteMissing = '';
    let blackMissing = '';
    
    for (const [pieceKey, initialCount] of Object.entries(INITIAL_COUNTS)) {
      const currentCount = gameState.material[pieceKey] || 0;
      const parts = pieceKey.split('-');
      const pColor = parts[0];
      const pType = parts[1];
      const val = PIECE_VALUES[pType] * currentCount;
      
      if (pColor === 'white') wScore += val;
      else bScore += val;
      
      const missingCount = initialCount - currentCount;
      if (missingCount > 0) {
        const emoji = EMOJIS[pieceKey];
        if (pColor === 'white') blackMissing += emoji.repeat(missingCount);
        else whiteMissing += emoji.repeat(missingCount);
      }
    }
    
    const diff = wScore - bScore;
    whiteScoreEl.innerHTML = `<span style="font-size: 1.2rem; margin-right: 5px;">${whiteMissing}</span> <span style="color: #94a3b8">${diff > 0 ? `+${diff}` : ''}</span>`;
    blackScoreEl.innerHTML = `<span style="font-size: 1.2rem; margin-right: 5px;">${blackMissing}</span> <span style="color: #94a3b8">${diff < 0 ? `+${Math.abs(diff)}` : ''}</span>`;
  }
}

function renderBoard() {
  boardEl.innerHTML = '';
  if (!gameState) return;

  for (let i = 0; i < 64; i++) {
    const sqEl = document.createElement('div');
    sqEl.className = 'square';
    
    // x, y calculation: x is i % 8, y is floor(i / 8)
    const x = i % 8;
    const y = Math.floor(i / 8);
    const isLight = (x + y) % 2 === 0;
    sqEl.classList.add(isLight ? 'light' : 'dark');

    if (selectedSquare === i) sqEl.classList.add('selected');
    if (legalMoves.includes(i)) sqEl.classList.add('valid-move');

    const piece = gameState.board[i];
    if (piece) {
      const pEl = document.createElement('div');
      pEl.className = 'piece';
      const pieceKey = `${piece.color}-${piece.type}`;
      pEl.style.backgroundImage = `url(${PIECE_IMAGES[pieceKey]})`;
      pEl.draggable = true;
      
      pEl.addEventListener('dragstart', (e) => {
        selectedSquare = i;
        fetchLegalMoves(i);
        e.dataTransfer.setData('text/plain', i);
        setTimeout(() => pEl.classList.add('dragging'), 0);
      });

      pEl.addEventListener('dragend', () => {
        pEl.classList.remove('dragging');
      });

      sqEl.appendChild(pEl);
    }

    sqEl.addEventListener('dragover', (e) => e.preventDefault());
    sqEl.addEventListener('drop', (e) => {
      e.preventDefault();
      const fromSq = parseInt(e.dataTransfer.getData('text/plain'));
      if (fromSq !== i && legalMoves.includes(i)) {
        makeMove(fromSq, i);
      } else {
        selectedSquare = null;
        legalMoves = [];
        renderBoard();
      }
    });

    // Click support
    sqEl.addEventListener('click', () => {
      if (selectedSquare === null && piece) {
        selectedSquare = i;
        fetchLegalMoves(i);
      } else if (selectedSquare !== null) {
        if (legalMoves.includes(i)) {
          makeMove(selectedSquare, i);
        } else {
          selectedSquare = null;
          legalMoves = [];
          renderBoard();
        }
      }
    });

    boardEl.appendChild(sqEl);
  }
}

resetBtn.addEventListener('click', resetGame);
undoBtn.addEventListener('click', undoGame);
fetchState();
