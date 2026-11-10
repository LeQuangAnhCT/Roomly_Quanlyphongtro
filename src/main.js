import { createApp } from 'vue'
import App from './App.vue'
import './style.css'
createApp(App).mount('#app')

// PWA installation with a network-first navigation worker. Does not cache
// authenticated data or stale JavaScript bundles.
if('serviceWorker' in navigator){
 window.addEventListener('load',()=>{
  navigator.serviceWorker.register('/sw.js').catch(err=>console.warn('PWA registration failed',err))
 })
}
