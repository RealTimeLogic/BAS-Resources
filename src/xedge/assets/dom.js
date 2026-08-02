export function el(t,a={},...c) {
    let e=document.createElement(t);
    for(let k in a) k=="text" ? e.textContent=a[k] : k=="html" ? e.innerHTML=a[k] : k in e ? e[k]=a[k] : e.setAttribute(k,a[k]);
    e.append(...c);
    return e;
}
export let q=(s,p=document)=>p.querySelector(s),qa=(s,p=document)=>p.querySelectorAll(s);
