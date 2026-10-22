import os, sqlite3, hashlib, hmac, secrets, time, re
from pathlib import Path
from fastapi import FastAPI, Request, HTTPException
from fastapi.responses import HTMLResponse, JSONResponse
from pydantic import BaseModel
from contextlib import contextmanager

app=FastAPI(title="CNY Pokémon Watch")
DB=Path(os.getenv("APP_DB","./cny.sqlite3"))
SECURE=os.getenv("COOKIE_SECURE","0")=="1"
TOWNS=["Solvay","Syracuse","Liverpool","Cicero","Clay","Baldwinsville","Camillus","DeWitt","Fayetteville","Manlius","Brewerton","Central Square","Phoenix","Fulton","Oswego","Oneida","Canastota","Verona"]
PRODUCTS=[("30th Celebration Booster Bundle",26.94,35),("Sylveon ex Box",29.99,40),("Greninja ex Box",29.99,40),("30th Celebration ETB",69.99,80),("Ultra-Premium Collection",179.99,200)]
@contextmanager
def db():
 DB.parent.mkdir(parents=True,exist_ok=True)
 c=sqlite3.connect(DB,timeout=10)
 c.row_factory=sqlite3.Row
 try:
  yield c;c.commit()
 finally:c.close()
with db() as c:
 c.executescript("""CREATE TABLE IF NOT EXISTS users(id INTEGER PRIMARY KEY, username TEXT UNIQUE COLLATE NOCASE, pw TEXT, status TEXT, role TEXT, created INTEGER);
 CREATE TABLE IF NOT EXISTS sessions(token TEXT PRIMARY KEY, uid INTEGER, csrf TEXT, expiry INTEGER);""")
def hashpw(p):
 s=secrets.token_bytes(16)
 return s.hex()+":"+hashlib.scrypt(p.encode(),salt=s,n=16384,r=8,p=1).hex()
def validpw(p,stored):
 try:
  s,h=stored.split(":")
  return hmac.compare_digest(hashlib.scrypt(p.encode(),salt=bytes.fromhex(s),n=16384,r=8,p=1).hex(),h)
 except Exception:return False
def username(u):
 if not re.fullmatch(r"[a-zA-Z0-9_]{3,24}",u):raise HTTPException(400,"Username must be 3–24 letters, digits or underscores")
 return u
initial=os.getenv("INITIAL_ADMIN_USERNAME","").strip()
secret=os.getenv("INITIAL_ADMIN_PASSWORD","")
if initial or secret:
 if not initial or len(secret)<12:raise RuntimeError("Configure both initial admin variables and a 12+ character password")
 username(initial)
 with db() as c:
  if not c.execute("SELECT 1 FROM users WHERE role='admin'").fetchone():
   if c.execute("SELECT 1 FROM users WHERE username=?",(initial,)).fetchone():raise RuntimeError("Admin username is already registered")
   c.execute("INSERT INTO users(username,pw,status,role,created) VALUES(?,?,?,?,?)",(initial,hashpw(secret),"approved","admin",int(time.time())))
class Creds(BaseModel):
 username:str
 password:str
class Status(BaseModel):
 status:str
def current(req,approved=True,admin=False,mutate=False):
 token=req.cookies.get("cny_session","")
 with db() as c:
  s=c.execute("SELECT u.id,u.username,u.role,u.status,s.csrf FROM sessions s JOIN users u ON u.id=s.uid WHERE s.token=? AND s.expiry>?",(hashlib.sha256(token.encode()).hexdigest(),int(time.time()))).fetchone() if token else None
 if not s:raise HTTPException(401,"Sign in required")
 v=dict(s)
 if approved and v["status"]!="approved":raise HTTPException(403,"Account awaiting approval")
 if admin and v["role"]!="admin":raise HTTPException(403,"Admin only")
 if mutate and not hmac.compare_digest(req.headers.get("X-CSRF-Token",""),v["csrf"]):raise HTTPException(403,"Invalid CSRF token")
 return v
@app.get("/health")
def health():return {"ok":True}
@app.get("/api/me")
def me(req:Request):
 try:return current(req,approved=False)
 except HTTPException:return {"signed_in":False}
@app.post("/api/register")
def register(p:Creds):
 u=username(p.username.strip())
 if not 12<=len(p.password)<=256:raise HTTPException(400,"Password must be 12–256 characters")
 with db() as c:
  if c.execute("SELECT 1 FROM users WHERE username=?",(u,)).fetchone():raise HTTPException(409,"Username already exists")
  c.execute("INSERT INTO users(username,pw,status,role,created) VALUES(?,?,?,?,?)",(u,hashpw(p.password),"pending","user",int(time.time())))
 return {"message":"Account created; await admin approval"}
@app.post("/api/login")
def login(p:Creds):
 with db() as c:
  u=c.execute("SELECT * FROM users WHERE username=?",(p.username.strip(),)).fetchone()
  if not u or not validpw(p.password,u["pw"]):raise HTTPException(401,"Invalid username or password")
  if u["status"] in ("disabled","rejected"):raise HTTPException(403,"Account not authorized")
  token=secrets.token_urlsafe(40)
  c.execute("INSERT INTO sessions(token,uid,csrf,expiry) VALUES(?,?,?,?)",(hashlib.sha256(token.encode()).hexdigest(),u["id"],secrets.token_urlsafe(32),int(time.time())+7*86400))
 out=JSONResponse({"status":u["status"]})
 out.set_cookie("cny_session",token,secure=SECURE,httponly=True,samesite="strict",max_age=604800)
 return out
@app.post("/api/logout")
def logout(req:Request):
 current(req,approved=False,mutate=True)
 with db() as c:c.execute("DELETE FROM sessions WHERE token=?",(hashlib.sha256(req.cookies["cny_session"].encode()).hexdigest(),))
 out=JSONResponse({"ok":True});out.delete_cookie("cny_session");return out
@app.get("/api/config")
def config(req:Request):
 current(req)
 return {"towns":TOWNS,"products":[{"name":n,"msrp":m,"maximum":cap} for n,m,cap in PRODUCTS],"live_stock":False}
@app.get("/api/admin/users")
def users(req:Request):
 current(req,admin=True)
 with db() as c:return {"users":[dict(x) for x in c.execute("SELECT id,username,status,role,created FROM users ORDER BY id DESC")]}
@app.post("/api/admin/users/{uid}/status")
def change(uid:int,p:Status,req:Request):
 current(req,admin=True,mutate=True)
 if p.status not in ("pending","approved","rejected","disabled"):raise HTTPException(400,"Invalid status")
 with db() as c:
  u=c.execute("SELECT role FROM users WHERE id=?",(uid,)).fetchone()
  if not u:raise HTTPException(404,"User not found")
  if u["role"]=="admin":raise HTTPException(403,"Cannot edit owner account")
  c.execute("UPDATE users SET status=? WHERE id=?",(p.status,uid))
  if p.status!="approved":c.execute("DELETE FROM sessions WHERE uid=?",(uid,))
 return {"ok":True}
PAGE="""<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><meta name="theme-color" content="#0d1022"><title>CNY Pokémon Watch</title><style>
*{box-sizing:border-box}body{margin:0;background:#0c1022;color:#eff2ff;font:16px system-ui,-apple-system,sans-serif}main{max-width:880px;padding:24px 18px;margin:auto}.hero{padding:20px 0}h1{font-size:30px;margin:8px 0}h2{font-size:20px}.muted{color:#a4acd0}.card{border:1px solid #343b61;background:#171d38;padding:20px;border-radius:18px;margin:15px 0}input,button{font:inherit;border-radius:11px;padding:13px;min-width:0}input{width:100%;background:#0b1026;border:1px solid #485278;color:white;margin:6px 0 10px}button{background:#595bea;border:0;color:white;cursor:pointer;margin:4px 3px 4px 0}button.alt{background:#313b5d}button.danger{background:#a13d5b}.row{display:flex;gap:8px;flex-wrap:wrap;align-items:center;justify-content:space-between}.price{font-weight:700;color:#92f5bd}.status{color:#acb9ff}#msg{padding:8px 0;min-height:30px}.hidden{display:none}.item{border-top:1px solid #3b4466;padding:12px 0}small{color:#acb5d0}code{color:#9caeff}</style></head><body><main><header class="hero"><small>PRIVATE MEMBER TEST</small><h1>⚡ CNY Pokémon Watch</h1><div class="muted">Solvay · Syracuse · Oswego · Verona</div></header><div id="msg"></div><section id="auth" class="card"><h2>Sign in</h2><input id="user" placeholder="Username" autocomplete="username"><input id="pw" type="password" placeholder="Password" autocomplete="current-password"><button onclick="login()">Sign in</button><button class="alt" onclick="register()">Create account</button><p class="muted">New accounts require administrator approval before accessing restock information.</p></section><section id="pending" class="card hidden"><h2>Approval pending</h2><p>Your account is awaiting administrator approval.</p><button onclick="refresh()">Check again</button><button class="alt" onclick="logout()">Sign out</button></section><section id="home" class="hidden"><div class="row"><h2 id="greeting"></h2><button class="alt" onclick="logout()">Sign out</button></div><div class="card"><h2>Watched products</h2><p class="muted">Reference MSRP and your suggested alert ceiling. Live store inventory checks are not connected in this version.</p><div id="products"></div></div><div class="card"><h2>Coverage</h2><div id="towns"></div></div><div id="admin" class="card hidden"><h2>🛡 Admin • Account Approvals</h2><p class="muted">Approve or disable individual member accounts.</p><div id="members"></div></div></section></main><script>
let csrf="";const $=id=>document.getElementById(id);const show=(id,on)=>$(id).classList.toggle("hidden",!on);const note=t=>$("msg").textContent=t;const esc=s=>String(s).replace(/[&<>"]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
async function api(path,method="GET",data){let o={method,credentials:"same-origin",headers:{"Content-Type":"application/json","X-CSRF-Token":csrf}};if(data)o.body=JSON.stringify(data);let r=await fetch(path,o);let j=await r.json();if(!r.ok)throw Error(j.detail||"Request failed");return j}
async function register(){try{let r=await api("/api/register","POST",{username:$("user").value,password:$("pw").value});note(r.message)}catch(e){note(e.message)}}
async function login(){try{await api("/api/login","POST",{username:$("user").value,password:$("pw").value});$("pw").value="";await refresh()}catch(e){note(e.message)}}
async function logout(){try{await api("/api/logout","POST")}catch(e){}csrf="";note("Signed out");await refresh()}
async function refresh(){let m=await api("/api/me");csrf=m.csrf||"";show("auth",!m.id);show("pending",!!m.id&&m.status!=="approved");show("home",!!m.id&&m.status==="approved");if(!m.id)return;note("");if(m.status!=="approved")return;$("greeting").textContent="Hello, "+m.username;let cfg=await api("/api/config");$("products").innerHTML=cfg.products.map(p=>'<div class="item"><b>'+esc(p.name)+'</b><div class="row"><small>MSRP $'+p.msrp.toFixed(2)+'</small><span class="price">Alert ≤ $'+p.maximum.toFixed(2)+'</span></div></div>').join("");$("towns").textContent=cfg.towns.join(" • ");show("admin",m.role==="admin");if(m.role==="admin")await members()}
async function members(){let r=await api("/api/admin/users");$("members").innerHTML=r.users.map(u=>'<div class="item"><div class="row"><b>'+esc(u.username)+'</b><span class="status">'+esc(u.status)+(u.role==="admin"?" (admin)":"")+'</span></div>'+(u.role==="admin"?"":'<div><button onclick="change('+u.id+',\'approved\')">Approve</button><button class="alt" onclick="change('+u.id+',\'pending\')">Pending</button><button class="danger" onclick="change('+u.id+',\'disabled\')">Disable</button></div>')+'</div>').join("")}
async function change(id,status){try{await api("/api/admin/users/"+id+"/status","POST",{status});await members();note("Account updated: "+status)}catch(e){note(e.message)}}refresh().catch(e=>note(e.message))
</script></body></html>"""
@app.get("/",response_class=HTMLResponse)
def index():return HTMLResponse(PAGE,headers={"Cache-Control":"no-store"})
