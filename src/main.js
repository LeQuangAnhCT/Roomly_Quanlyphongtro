import { createApp } from 'vue'
import App from './App.vue'
import './style.css'

// Surface fatal client-side errors instead of leaving a blank screen.
// Never display auth tokens, URLs or response bodies in this recovery UI.
function showStartupError(){
 let panel=document.getElementById('roomly-error-screen')
 if(panel)return
 panel=document.createElement('div')
 panel.id='roomly-error-screen'
 panel.setAttribute('role','alert')
 panel.style.cssText='position:fixed;inset:0;z-index:99999;background:#f8f8f8;display:grid;place-items:center;padding:24px;color:#111;font:14px system-ui,sans-serif'
 panel.innerHTML='<div style="max-width:370px;width:100%;background:white;border:1px solid #ddd;border-radius:16px;padding:24px;text-align:center"><h1 style="font-size:25px">ROOMLY</h1><h2 style="font-size:17px;margin-top:16px">Không thể hiển thị ứng dụng</h2><p style="color:#666;line-height:1.6">Đã xảy ra lỗi giao diện. Bạn có thể thử tải lại mà không mất lịch và dữ liệu nhóm.</p><button type="button" id="roomly-error-retry" style="background:#111;border:0;border-radius:10px;padding:12px 18px;color:white;font:inherit">Tải lại ứng dụng</button></div>'
 document.body.appendChild(panel)
 panel.querySelector('#roomly-error-retry')?.addEventListener('click',()=>location.reload())
}
window.addEventListener('error',event=>{
 if(event.message&&/Script error|Failed to fetch dynamically imported module|Cannot read properties|Vue warn/.test(String(event.message)))
  showStartupError()
})
const app=createApp(App)
app.config.errorHandler=(err,instance,info)=>{
 console.error('Roomly UI error:',info,err)
 showStartupError()
}
app.mount('#app')
// Register a network-first PWA worker; auth/data and JS bundles are not cached.
if('serviceWorker' in navigator){
 window.addEventListener('load',()=>{
  navigator.serviceWorker.register('/sw.js').catch(err=>console.warn('PWA registration failed',err))
 })
}
