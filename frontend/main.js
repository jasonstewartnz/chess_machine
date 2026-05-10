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
let currentMode = 'game';
let selectedPalettePiece = null; // {color, type}

const boardEl = document.getElementById('chessboard');
const statusEl = document.getElementById('status-indicator');
const resetBtn = document.getElementById('reset-btn');
const undoBtn = document.getElementById('undo-btn');
const whiteScoreEl = document.getElementById('white-score');
const blackScoreEl = document.getElementById('black-score');
// dropdown for mode selection
const modeSelect = document.getElementById('mode-select');
const whitePalette = document.getElementById('white-palette');
const blackPalette = document.getElementById('black-palette');
const playerInfos = document.querySelectorAll('.player-info');
const fenInput = document.getElementById('fen-input');
const copyFenBtn = document.getElementById('copy-fen-btn');
const loadFenBtn = document.getElementById('load-fen-btn');
const clearBoardBtn = document.getElementById('clear-board-btn');

let draggedPiece = null; // {source: 'board'|'palette', sq: number, color: string, type: string}

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
  
  clearBoardBtn.style.display = explore ? 'inline-block' : 'none';
  
  if (!explore) {
    selectedPalettePiece = null;
    renderPalettes();
  }
}

function renderPalettes() {
  whitePalette.innerHTML = '';
  blackPalette.innerHTML = '';
  
  const types = ['pawn', 'knight', 'bishop', 'rook', 'queen', 'king'];
  
  ['white', 'black'].forEach(color => {
    const container = color === 'white' ? whitePalette : blackPalette;
    types.forEach(type => {
      const btn = document.createElement('div');
      btn.className = 'palette-piece';
      if (selectedPalettePiece && selectedPalettePiece.color === color && selectedPalettePiece.type === type) {
        btn.classList.add('selected');
      }
      
      const img = document.createElement('img');
      img.src = PIECE_IMAGES[`${color}-${type}`];
      btn.appendChild(img);
      
      btn.draggable = true;
      btn.addEventListener('dragstart', (e) => {
        draggedPiece = { source: 'palette', color, type };
        e.dataTransfer.setData('text/plain', ''); // Required for some browsers
        btn.classList.add('dragging');
      });
      btn.addEventListener('dragend', () => {
        btn.classList.remove('dragging');
      });

      btn.onclick = () => {
        if (selectedPalettePiece && selectedPalettePiece.color === color && selectedPalettePiece.type === type) {
          selectedPalettePiece = null;
        } else {
          selectedPalettePiece = { color, type };
        }
        renderPalettes();
      };
      container.appendChild(btn);
    });
  });
}
renderPalettes();

// Toggle mode on button click
modeSelect.addEventListener('change', async () => {
  const newMode = modeSelect.value; // 'game' or 'explore'
  await fetch(`${API_BASE}/set-mode?mode=${newMode}`, {method: 'POST'});
  // keep dropdown in sync (value already set)
  currentMode = newMode;
  applyMode(newMode);
  fetchState();
});

async function fetchState() {
  try {
    const res = await fetch(`${API_BASE}/state?t=${Date.now()}`);
    gameState = await res.json();
    // keep UI mode in sync with server response
    if (gameState.mode && gameState.mode !== currentMode) {
      currentMode = gameState.mode;
      modeSelect.value = currentMode;
      applyMode(currentMode);
    }
    renderBoard();
    updateStatus();
    updateCaptured();
    if (gameState.fen) {
      fenInput.value = gameState.fen;
    }
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
      updateCaptured();
    }
  } catch (err) {
    console.error(err);
  }
}

async function movePieceExplore(from, to) {
  const piece = gameState.board[from];
  if (!piece) return;
  
  // Optimistic update
  const oldBoard = [...gameState.board];
  gameState.board[to] = piece;
  gameState.board[from] = null;
  selectedSquare = null;
  legalMoves = [];
  renderBoard();

  try {
    const res = await fetch(`${API_BASE}/move-piece-explore?from=${from}&to=${to}`, { method: 'POST' });
    const data = await res.json();
    if (data.success) {
      fetchState();
    }
  } catch (err) {
    gameState.board = oldBoard;
    renderBoard();
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

async function placePiece(sq, color, type) {
  // Optimistic update
  const oldBoard = [...gameState.board];
  gameState.board[sq] = { color, type };
  renderBoard();

  try {
    const res = await fetch(`${API_BASE}/place-piece?sq=${sq}&color=${color}&type=${type}`, { method: 'POST' });
    const data = await res.json();
    if (data.success) {
      fetchState();
    }
  } catch (err) {
    gameState.board = oldBoard;
    renderBoard();
    console.error(err);
  }
}

async function removePiece(sq) {
  try {
    const res = await fetch(`${API_BASE}/remove-piece?sq=${sq}`, { method: 'POST' });
    const data = await res.json();
    if (data.success) {
      fetchState();
    }
  } catch (err) {
    console.error(err);
  }
}

async function clearBoard() {
  try {
    const res = await fetch(`${API_BASE}/clear-board`, { method: 'POST' });
    const data = await res.json();
    if (data.success) {
      fetchState();
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
    statusEl.innerHTML = `${color} to move`;
  }
}

// Update captured piece display for game mode
function updateCaptured() {
  if (!gameState) return;
  const material = gameState.material || {};
  const counts = {};
  
  // material may be an array of [key, value] pairs or an object
  if (Array.isArray(material)) {
    material.forEach(pair => {
      const key = typeof pair[0] === 'string' ? pair[0].toLowerCase() : '';
      const val = pair[1];
      counts[key] = val;
    });
  } else {
    Object.entries(material).forEach(([k, v]) => {
      counts[k.toLowerCase()] = v;
    });
  }

  if (currentMode !== 'game') {
    whiteScoreEl.innerHTML = '';
    blackScoreEl.innerHTML = '';
    return;
  }

  let wScoreTotal = 0;
  let bScoreTotal = 0;
  let whiteMissing = ''; // pieces captured by Black (shown at top)
  let blackMissing = ''; // pieces captured by White (shown at bottom)

  for (const [pieceKey, initialCount] of Object.entries(INITIAL_COUNTS)) {
    const currentCount = counts[pieceKey] || 0;
    const parts = pieceKey.split('-');
    const pColor = parts[0];
    const pType = parts[1];
    const val = PIECE_VALUES[pType] * currentCount;

    if (pColor === 'white') wScoreTotal += val;
    else bScoreTotal += val;

    const missingCount = initialCount - currentCount;
    if (missingCount > 0) {
      const emoji = EMOJIS[pieceKey];
      if (pColor === 'white') {
        whiteMissing += emoji.repeat(missingCount);
      } else {
        blackMissing += emoji.repeat(missingCount);
      }
    }
  }

  const diff = wScoreTotal - bScoreTotal;
  // Top panel (Black) shows white pieces captured by Black
  blackScoreEl.innerHTML = `<span style="font-size: 1.2rem; margin-right: 5px;">${whiteMissing}</span> <span style="color: #94a3b8">${diff < 0 ? `+${Math.abs(diff)}` : ''}</span>`;
  // Bottom panel (White) shows black pieces captured by White
  whiteScoreEl.innerHTML = `<span style="font-size: 1.2rem; margin-right: 5px;">${blackMissing}</span> <span style="color: #94a3b8">${diff > 0 ? `+${diff}` : ''}</span>`;
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
      const pieceKey = `${piece.color}-${piece.type}`;
      pEl.className = `piece ${pieceKey}`;
      pEl.style.backgroundImage = `url(${PIECE_IMAGES[pieceKey]})`;
      
      // Cursor & Turn enforcement
      const isTurn = currentMode === 'explore' || piece.color === (gameState.activeColor || 'white');
      pEl.style.cursor = isTurn ? 'grab' : 'default';
      pEl.draggable = isTurn;
      
      pEl.addEventListener('dragstart', (e) => {
        draggedPiece = { source: 'board', sq: i, color: piece.color, type: piece.type };
        e.dataTransfer.setData('text/plain', i);
        selectedSquare = i;
        if (currentMode === 'game') fetchLegalMoves(i);
        setTimeout(() => pEl.classList.add('dragging'), 0);
      });

      pEl.addEventListener('dragend', () => {
        pEl.classList.remove('dragging');
        sqEl.classList.remove('drag-over');
      });

      sqEl.appendChild(pEl);
    }

    // Square Drop Handling
    sqEl.addEventListener('dragover', (e) => {
      e.preventDefault();
      sqEl.classList.add('drag-over');
    });

    sqEl.addEventListener('dragleave', () => {
      sqEl.classList.remove('drag-over');
    });

    sqEl.addEventListener('drop', (e) => {
      e.preventDefault();
      e.stopPropagation(); // Prevent the document-level removal listener from firing
      sqEl.classList.remove('drag-over');
      if (!draggedPiece) return;

      if (draggedPiece.source === 'palette') {
        placePiece(i, draggedPiece.color, draggedPiece.type);
      } else if (draggedPiece.source === 'board') {
        if (currentMode === 'explore') {
          movePieceExplore(draggedPiece.sq, i);
        } else {
          makeMove(draggedPiece.sq, i);
        }
      }
      draggedPiece = null;
      selectedSquare = null;
      legalMoves = [];
    });

    // Click support
    sqEl.addEventListener('click', () => {
      if (currentMode === 'explore' && selectedPalettePiece) {
        placePiece(i, selectedPalettePiece.color, selectedPalettePiece.type);
        return;
      }

      if (currentMode === 'explore' && !selectedPalettePiece && gameState.board[i]) {
        removePiece(i);
        return;
      }

      if (selectedSquare === i) {
        selectedSquare = null;
        legalMoves = [];
        renderBoard();
      } else if (gameState && gameState.board[i] && gameState.board[i].color === (gameState.activeColor || 'white')) {
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
clearBoardBtn.addEventListener('click', clearBoard);

// Drag OFF board to remove (Explore mode)
document.addEventListener('dragover', (e) => e.preventDefault());
document.addEventListener('drop', (e) => {
  if (currentMode === 'explore' && draggedPiece && draggedPiece.source === 'board') {
    // If we dropped on something that isn't a square, remove it
    if (!e.target.closest('.square')) {
      removePiece(draggedPiece.sq);
    }
  }
  draggedPiece = null;
});

copyFenBtn.addEventListener('click', () => {
  fenInput.select();
  document.execCommand('copy');
  const originalText = copyFenBtn.textContent;
  copyFenBtn.textContent = 'Copied!';
  setTimeout(() => copyFenBtn.textContent = originalText, 2000);
});

loadFenBtn.addEventListener('click', async () => {
  const fen = fenInput.value.trim();
  if (!fen) return;
  try {
    const res = await fetch(`${API_BASE}/load-fen?fen=${encodeURIComponent(fen)}`, { method: 'POST' });
    const data = await res.json();
    if (data.success) {
      gameState = data.state;
      selectedSquare = null;
      legalMoves = [];
      renderBoard();
      updateStatus();
      updateCaptured();
    } else {
      alert('Invalid FEN');
    }
  } catch (err) {
    console.error(err);
  }
});

fetchState();
applyMode(currentMode);
