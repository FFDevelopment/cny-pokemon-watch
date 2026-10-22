import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";
import { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from "./config.js";
const $ = id=>document.getElementById(id);
const message=(s)=>{$("notice").textContent=s||""};
const visible=(id,on)=>$(id).classList.toggle("hidden",!on);
const fmt=n=>n===null||n===undefined?"Price unavailable":"$"+Number(n).toFixed(2);
const categories={booster_box:"Booster box",booster_bundle:"Booster bundle",etb:"Elite Trainer Box",tin:"Tin",collection:"Collection",blister:"Blister",other:"Other"};
const towns=["Solvay","Syracuse","Liverpool","Cicero","Clay","Baldwinsville","Camillus","DeWitt","Fayetteville","Manlius","Brewerton","Central Square","Phoenix","Fulton","Oswego","Oneida","Canastota","Verona"];
let db=null,profile=null,session=null,products=[],stores=[],offers=[],watches=[],alerts=[];
function el(tag,txt,cls){let n=document.createElement(tag);if(txt!==undefined)n.textContent=String(txt);if(cls)n.className=cls;return n}
function btn(txt,fn,cls="secondary"){let n=el("button",txt,cls);n.type="button";n.onclick=()=>Promise.resolve(fn()).catch(handle);return n}
function handle(e){console.error(e);message(e?.message||"Operation failed")}
async function query(p){const r=await p;if(r.error)throw r.error;return r.data}
function tab(name){document.querySelectorAll(".tabpage").forEach(n=>visible(n.id,n.id===name+"Tab"));document.querySelectorAll("[data-tab]").forEach(n=>n.classList.toggle("active",n.dataset.tab===name))}
document.querySelectorAll("[data-tab]").forEach(n=>n.onclick=()=>{tab(n.dataset.tab);if(n.dataset.tab==="admin")void loadAdmin().catch(handle)});
function showAuth(){profile=null;session=null;$("identity").textContent="";visible("authPanel",true);visible("pendingPanel",false);visible("appPanel",false);visible("signOut",false)}
async function refreshAuth(){
  const {data:{session:s},error}=await db.auth.getSession();if(error)throw error;
  if(!s){showAuth();return}
  session=s;
  profile=await query(db.from("cny_profiles").select("id,username,status,role").eq("id",s.user.id).single());
  $("identity").textContent=profile.username+" · "+profile.status;
  visible("signOut",true);visible("authPanel",false);
  if(profile.status!=="approved"){visible("appPanel",false);visible("pendingPanel",true);$("pendingStatus").textContent=profile.username+" is "+profile.status;return}
  visible("pendingPanel",false);visible("appPanel",true);visible("adminTabButton",profile.role==="admin");
  await loadProducts(); await loadStores(); await Promise.all([loadWatches(),loadOffers(),loadAlerts()]);
  if(profile.role==="admin")await loadAdmin();
}
function listenForm(id,fn){$(id).addEventListener("submit",async ev=>{ev.preventDefault();const b=ev.submitter;if(b)b.disabled=true;try{await fn()}catch(e){handle(e)}finally{if(b)b.disabled=false}})}
listenForm("registerForm",async()=>{
 const username=$("newUsername").value.trim(),email=$("newEmail").value.trim(),password=$("newPassword").value;
 if(!/^[a-zA-Z0-9_]{3,24}$/.test(username))throw Error("Invalid username");
 if(password.length<12)throw Error("Use at least 12 characters");
 const {error}=await db.auth.signUp({email,password,options:{data:{username},emailRedirectTo:new URL("./",location.href).href}});
 if(error)throw error;
 $("newPassword").value="";message("Account request submitted. Verify your email if required, then await administrator approval.");
});
listenForm("loginForm",async()=>{
 const {error}=await db.auth.signInWithPassword({email:$("loginEmail").value.trim(),password:$("loginPassword").value});
 if(error)throw error;
 $("loginPassword").value="";message("");await refreshAuth();
});
$("signOut").onclick=async()=>{try{const {error}=await db.auth.signOut();if(error)throw error;message("Signed out");showAuth()}catch(e){handle(e)}};
$("refreshStatus").onclick=()=>refreshAuth().catch(handle);
$("refreshCatalog").onclick=()=>loadProducts().catch(handle);
$("refreshOffers").onclick=()=>loadOffers().catch(handle);
$("refreshAlerts").onclick=()=>loadAlerts().catch(handle);
$("productSearch").oninput=renderProducts;$("categoryFilter").onchange=renderProducts;
async function loadProducts(){products=await query(db.from("cny_products").select("slug,name,expansion,category,release_date,official_url").eq("available",true).order("release_date",{ascending:false}).limit(500));renderProducts()}
function renderProducts(){
 const q=$("productSearch").value.trim().toLowerCase(),category=$("categoryFilter").value,box=$("productResults");box.replaceChildren();
 const list=products.filter(x=>(!category||x.category===category)&&(!q||[x.name,x.expansion,x.category].join(" ").toLowerCase().includes(q)));
 if(!list.length){box.append(el("p","No matching catalog entries.","muted"));return}
 for(const p of list){
 const c=el("article",undefined,"subcard");c.append(el("span",categories[p.category]||p.category,"eyebrow"),el("h3",p.name),el("div",p.expansion,"muted small"),el("div",p.release_date?"Release: "+p.release_date:"Release date unavailable","muted small"));
 const row=el("div",undefined,"row");row.append(btn(watches.some(w=>w.product_slug===p.slug)?"Watching ✓":"Watch product",()=>addWatch(p.slug)));
 if(p.official_url){const a=el("a","Official details ↗");a.href=p.official_url;a.target="_blank";a.rel="noopener noreferrer";row.append(a)}c.append(row);box.append(c)}
}
async function addWatch(slug){await query(db.from("cny_watches").upsert({user_id:session.user.id,product_slug:slug},{onConflict:"user_id,product_slug"}));message("Added to watchlist");await loadWatches();renderProducts()}
async function loadWatches(){watches=await query(db.from("cny_watches").select("user_id,product_slug,max_price,towns").eq("user_id",session.user.id).limit(500));renderWatches();renderProducts()}
function renderWatches(){const b=$("watchResults");b.replaceChildren();if(!watches.length){b.append(el("p","Your watchlist is empty. Open Products to add items.","muted"));return}
 for(const w of watches){
 const p=products.find(x=>x.slug===w.product_slug),section=el("div",undefined,"item");section.append(el("strong",p?.name||w.product_slug));
 const row=el("div",undefined,"twocol"),left=el("div"),right=el("div");left.append(el("label","Maximum price ($; blank for any)"));const price=el("input");price.type="number";price.min="0.01";price.step="0.01";price.value=w.max_price??"";left.append(price);
 right.append(el("label","Towns (comma separated, blank = all)"));const t=el("input");t.value=(w.towns||[]).join(", ");t.placeholder="Syracuse, Oswego";right.append(t);row.append(left,right);section.append(row);
 section.append(btn("Save filters",async()=>{const raw=t.value.split(",").map(z=>z.trim()).filter(Boolean);const unique=[...new Set(raw)];if(unique.some(z=>!towns.includes(z)&&z!=="Online"))throw Error("Use supported towns: "+towns.join(", "));const max=price.value?Number(price.value):null;if(max!==null&&(!Number.isFinite(max)||max<=0||max>100000))throw Error("Invalid price");await query(db.from("cny_watches").update({max_price:max,towns:unique}).eq("user_id",session.user.id).eq("product_slug",w.product_slug));message("Filters saved");await loadWatches()}));
 section.append(btn("Remove",async()=>{await query(db.from("cny_watches").delete().eq("user_id",session.user.id).eq("product_slug",w.product_slug));await loadWatches();renderProducts()},"danger"));b.append(section)}
}
async function loadOffers(){offers=await query(db.from("cny_offers").select("id,product_slug,store_id,product_url,price,stock_status,verified_at").order("updated_at",{ascending:false}).limit(250));renderOffers()}
function renderOffers(){const b=$("offerResults");b.replaceChildren();if(!offers.length){b.append(el("p","No verified retailer reports have been recorded yet. No availability is being claimed.","muted"));return}
 for(const o of offers){const p=products.find(x=>x.slug===o.product_slug),store=stores.find(x=>x.id===o.store_id);const row=el("div",undefined,"item");row.append(el("strong",p?.name||o.product_slug),el("p",(store?.name||"Retailer")+" · "+(store?.town||"Location pending")+" · "+fmt(o.price),"muted"));const stale=o.stock_status==="in_stock"&&(!o.verified_at||Date.now()-Date.parse(o.verified_at)>60*60*1000);row.append(el("p","Stock: "+(stale?"previously reported in stock — STALE (recheck)":o.stock_status.replaceAll("_"," "))+" · "+(o.verified_at?"Checked "+new Date(o.verified_at).toLocaleString():"Not verified"),stale?"warn small":"small"));if(o.product_url){const a=el("a","Retailer link ↗");a.href=o.product_url;a.target="_blank";a.rel="noopener noreferrer";row.append(a)}b.append(row)}}
async function loadStores(){stores=await query(db.from("cny_stores").select("id,retailer,name,town,address,website,online").eq("active",true).limit(500));renderStores()}
function renderStores(){const box=$("storeResults");box.replaceChildren();for(const shop of stores){const c=el("article",undefined,"subcard");c.append(el("strong",shop.name),el("div",shop.town+(shop.online?" · Online retailer":""),"muted small"));if(shop.address)c.append(el("div",shop.address,"muted small"));if(shop.website){const a=el("a","Visit store website ↗");a.href=shop.website;a.target="_blank";a.rel="noopener noreferrer";c.append(a)}c.append(el("div","Inventory not confirmed","warn small"));box.append(c)}}
async function loadAlerts(){alerts=await query(db.from("cny_notifications").select("id,title,body,created_at,read_at").order("created_at",{ascending:false}).limit(100));$("alertCount").textContent=alerts.filter(a=>!a.read_at).length||"";const b=$("alertResults");b.replaceChildren();if(!alerts.length){b.append(el("p","No alerts yet.","muted"));return}
 for(const a of alerts){const r=el("div",undefined,"item");r.append(el("strong",a.title),el("p",a.body),el("p",new Date(a.created_at).toLocaleString(),"muted small"));if(!a.read_at)r.append(btn("Mark read",async()=>{await query(db.from("cny_notifications").update({read_at:new Date().toISOString()}).eq("id",a.id).eq("user_id",session.user.id));await loadAlerts()}));b.append(r)}}
async function loadAdmin(){if(profile?.role!=="admin")return;await loadStores();await loadOffers();const members=await query(db.from("cny_profiles").select("id,username,status,role,created_at").order("created_at",{ascending:false}).limit(250));const box=$("memberResults");box.replaceChildren();for(const m of members){const r=el("div",undefined,"item"),line=el("div",undefined,"row spread");line.append(el("strong",m.username),el("span",m.status+(m.role==="admin"?" · admin":""),"flag"));r.append(line);if(m.role!=="admin"){const a=el("div",undefined,"actions");for(const status of ["approved","pending","rejected","disabled"])a.append(btn(status,async()=>{await query(db.from("cny_profiles").update({status}).eq("id",m.id).eq("role","member"));message("Updated "+m.username+" to "+status);await loadAdmin()},status==="disabled"?"danger":"secondary"));r.append(a)}box.append(r)}
 for(const [id,list,label] of [["adminOfferProduct",products,"name"],["adminOfferStore",stores,"name"]]){const sel=$(id);sel.replaceChildren();for(const item of list){let o=document.createElement("option");o.value=id==="adminOfferProduct"?item.slug:item.id;o.textContent=item[label]+(item.town?" ("+item.town+")":"");sel.append(o)}}
}
listenForm("productForm",async()=>{await query(db.from("cny_products").insert({slug:$("adminProductSlug").value.trim(),name:$("adminProductName").value.trim(),expansion:$("adminProductExpansion").value.trim(),category:$("adminProductCategory").value,release_date:$("adminProductRelease").value||null,official_url:$("adminProductUrl").value.trim()||null}));message("Product saved");$("productForm").reset();await loadProducts();await loadAdmin()});
listenForm("storeForm",async()=>{await query(db.from("cny_stores").insert({retailer:$("adminStoreRetailer").value.trim(),name:$("adminStoreName").value.trim(),town:$("adminStoreTown").value.trim(),address:$("adminStoreAddress").value.trim()||null,website:$("adminStoreWebsite").value.trim()||null,online:$("adminStoreOnline").checked}));message("Retailer saved");$("storeForm").reset();await loadAdmin()});
listenForm("offerForm",async()=>{
 const status=$("adminOfferStatus").value,url=$("adminOfferUrl").value.trim(),price=$("adminOfferPrice").value;
 if(!url.startsWith("https://"))throw Error("Retailer URL must use HTTPS");
 if(status==="in_stock"&&!confirm("Did you personally verify this offer is actually in stock? This may trigger member alerts."))return;
 await query(db.from("cny_offers").upsert({product_slug:$("adminOfferProduct").value,store_id:$("adminOfferStore").value,product_url:url,price:price?Number(price):null,stock_status:status,verified_at:status==="unknown"?null:new Date().toISOString(),verification_method:status==="unknown"?null:"admin_confirmation"},{onConflict:"product_slug,store_id,product_url"}));message("Report saved");$("offerForm").reset();await loadOffers();await loadAlerts();
});
async function init(){
 if(!SUPABASE_URL||!SUPABASE_PUBLISHABLE_KEY){visible("setupPanel",true);message("Dedicated production database setup is required.");return}
 db=createClient(SUPABASE_URL,SUPABASE_PUBLISHABLE_KEY,{auth:{autoRefreshToken:true,persistSession:true,detectSessionInUrl:true}});
 await refreshAuth();db.auth.onAuthStateChange((event)=>{if(event==="SIGNED_OUT")showAuth()});
}
init().catch(e=>{handle(e);visible("setupPanel",true)});
