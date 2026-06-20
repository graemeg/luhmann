// Live reload over WebSocket.
//
// A reload signal that arrives while this tab is backgrounded is remembered
// (browsers throttle background tabs and may defer the reload), and applied
// the moment the tab becomes visible again. This keeps listing pages such as
// /tags/<tag> in sync after you edit a note in another tab.
(function () {
  var reloadPending = false;

  function doReload() { window.location.reload(); }

  function onSignal() {
    if (document.visibilityState === 'visible') {
      doReload();
    } else {
      reloadPending = true;
    }
  }

  var socket = new WebSocket(location.origin.replace(/^http/, 'ws') + '/ws');
  socket.addEventListener('message', onSignal);

  document.addEventListener('visibilitychange', function () {
    if (reloadPending && document.visibilityState === 'visible') {
      reloadPending = false;
      doReload();
    }
  });
})();

function currentNote() {
  var loc = location.pathname;
  if (loc === '/' || loc === '') return 'index.adoc';
  return loc.replace(/^\//, '').replace(/\.html$/, '.adoc');
}

function focusSearch() {
  var input = document.getElementsByName('q').item(0);
  if (input) { input.focus(); input.select(); }
}

function hideToast() {
  var t = document.getElementById('luh-toast');
  if (t) t.remove();
}

function showToast(text) {
  hideToast();
  var t = document.createElement('div');
  t.id = 'luh-toast';
  t.appendChild(document.createTextNode(text));
  document.body.appendChild(t);
  setTimeout(hideToast, 1200);
}

function keyListener(e) {
  if (document.activeElement && e.key === 'Escape') {
    document.activeElement.blur();
  } else if (e.target.tagName === 'BODY') {
    if (e.key === '/') {
      e.preventDefault();
      focusSearch();
    } else if (e.key === 'e') {
      showToast('Launching editor...');
      var xhr = new XMLHttpRequest();
      xhr.open('GET', '/api/edit?note=' + encodeURIComponent(currentNote()));
      xhr.send();
    } else if (e.key === 'g') {
      location.href = '/graph?note=' + encodeURIComponent(currentNote());
    }
  }
}

document.addEventListener('keydown', keyListener);
