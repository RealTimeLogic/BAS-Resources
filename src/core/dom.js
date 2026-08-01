export function el(n,p,...c){
  const e=document.createElement(n);
  if(typeof p==="string")e.textContent=p;
  else if(p)Object.assign(e,p);
  e.append(...c);
  return e;
}

export function on(r,n,s,f,o){
  const h=e=>{
    const t=e.target?.closest?.(s);
    if(t&&r.contains(t))f(e,t);
  };
  r.addEventListener(n,h,o);
  return()=>r.removeEventListener(n,h,o);
}
