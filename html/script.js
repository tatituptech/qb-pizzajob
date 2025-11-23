window.addEventListener('message', (event) => {
  const d = event.data
  if (!d) return
  if (d.type === 'openDetails') {
    const el = document.getElementById('app')
    const details = document.getElementById('details')
    let pretty = ''
    try {
      pretty = JSON.stringify(d.data, null, 2)
    } catch (err) {
      pretty = String(d.data)
    }
    details.textContent = pretty
    window.__currentDetails = d.data || {}
    el.classList.remove('hidden')
  } else if (d.type === 'copy') {
    const text = d.text || ''
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(() => {
        fetch(`https://${GetParentResourceName()}/copied`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json; charset=UTF-8' },
          body: JSON.stringify({ ok: true })
        }).catch(() => {})
      }).catch(() => {})
    } else {
      const input = document.createElement('textarea')
      input.value = text
      document.body.appendChild(input)
      input.select()
      document.execCommand('copy')
      document.body.removeChild(input)
      fetch(`https://${GetParentResourceName()}/copied`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify({ ok: true })
      }).catch(() => {})
    }
  }
})

document.getElementById('closeBtn').addEventListener('click', () => {
  document.getElementById('app').classList.add('hidden')
  fetch(`https://${GetParentResourceName()}/close`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify({ })
  }).then(() => {})
})

document.getElementById('copyBtn').addEventListener('click', () => {
  const data = window.__currentDetails || {}
  const cid = data.citizenid || data.citizen || ""
  const text = cid || ""
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(text).then(() => {
      fetch(`https://${GetParentResourceName()}/copied`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify({ ok: true })
      }).catch(() => {})
    }).catch(() => {})
  } else {
    const input = document.createElement('textarea')
    input.value = text
    document.body.appendChild(input)
    input.select()
    document.execCommand('copy')
    document.body.removeChild(input)
    fetch(`https://${GetParentResourceName()}/copied`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify({ ok: true })
    }).catch(() => {})
  }
})
