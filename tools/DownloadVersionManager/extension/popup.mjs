document.querySelector('#version').textContent = chrome.runtime.getManifest().version + ' 평가판';
document.querySelector('#check').addEventListener('click', async () => {
  const output = document.querySelector('#result'); output.textContent = '연결을 확인하고 있습니다.';
  try {
    const r = await chrome.runtime.sendMessage({type: 'handshake'});
    output.textContent = r?.ok ? '연결됐습니다. 다음 다운로드부터 정리합니다.' : '연결하지 못했습니다. 설치 파일과 확장 버전을 확인해 주세요.';
  } catch { output.textContent = '연결하지 못했습니다. 설치 안내를 확인해 주세요.'; }
});
