// Central de Relatórios — administração de usuários (criar / resetar senha)
// Só executa para quem é admin ativo na Central (central.perfis).
// A senha padrão fica em central.configuracoes (chave 'senha_padrao').
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function resp(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return resp(405, { error: "Método não permitido" });

  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
  const db = admin.schema("central");

  // 1) quem está chamando precisa ser admin ativo
  const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
  const { data: caller, error: callerErr } = await admin.auth.getUser(jwt);
  if (callerErr || !caller?.user) return resp(401, { error: "Sessão inválida. Entre novamente." });
  const { data: perfil } = await db.from("perfis")
    .select("is_admin, ativo, must_change_password").eq("id", caller.user.id).maybeSingle();
  if (!perfil || !perfil.is_admin || !perfil.ativo || perfil.must_change_password) {
    return resp(403, { error: "Acesso restrito ao administrador." });
  }

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return resp(400, { error: "Requisição inválida" }); }

  const { data: cfg } = await db.from("configuracoes").select("valor").eq("chave", "senha_padrao").maybeSingle();
  const senhaPadrao = cfg?.valor;
  if (!senhaPadrao || senhaPadrao.length < 8) return resp(500, { error: "Senha padrão não configurada." });

  // 2) criar usuário
  if (body.acao === "criar") {
    const login = String(body.login || "").trim().toLowerCase();
    const nome = String(body.nome || "").trim().slice(0, 80);
    const isAdmin = body.is_admin === true;
    if (!/^[a-z0-9._-]{2,40}$/.test(login)) return resp(400, { error: "Usuário de rede inválido (ex.: joao.silva)." });
    // e-mail é opcional: sem e-mail corporativo, o Auth usa um endereço técnico interno
    const emailInformado = String(body.email || "").trim().toLowerCase();
    if (emailInformado && !EMAIL_RE.test(emailInformado)) return resp(400, { error: "E-mail inválido." });
    const email = emailInformado || `${login}@usuarios.tecnolimp.local`;
    if (nome.length < 2) return resp(400, { error: "Informe o nome." });
    const { data: loginUsado } = await db.from("perfis").select("id").eq("login", login).maybeSingle();
    if (loginUsado) return resp(409, { error: "Este usuário de rede já está cadastrado na Central." });

    let userId: string | null = null;
    let jaExistia = false;
    const { data: criado, error: criarErr } = await admin.auth.admin.createUser({
      email, password: senhaPadrao, email_confirm: true,
    });
    if (criado?.user) {
      userId = criado.user.id;
    } else if (criarErr && /already|registered|exists/i.test(criarErr.message)) {
      // e-mail já existe no Auth (outro app interno): só vincula o perfil na Central
      for (let page = 1; page <= 50 && !userId; page++) {
        const { data: lista } = await admin.auth.admin.listUsers({ page, perPage: 200 });
        const u = lista?.users?.find((x) => (x.email || "").toLowerCase() === email);
        if (u) userId = u.id;
        if (!lista || lista.users.length < 200) break;
      }
      jaExistia = true;
    }
    if (!userId) return resp(400, { error: criarErr?.message || "Não foi possível criar o usuário." });

    const { data: existente } = await db.from("perfis").select("id").eq("id", userId).maybeSingle();
    if (existente) return resp(409, { error: "Este e-mail já está vinculado a outro usuário da Central." });

    const { error: perfilErr } = await db.from("perfis").insert({
      id: userId, email, login, nome, is_admin: isAdmin,
      must_change_password: !jaExistia,
    });
    if (perfilErr) return resp(500, { error: "Usuário criado, mas falhou ao gravar o perfil." });
    return resp(200, { ok: true, id: userId, ja_existia: jaExistia });
  }

  // 3) resetar senha para a padrão (obriga troca no próximo acesso)
  if (body.acao === "resetar_senha") {
    const id = String(body.usuario_id || "");
    if (!/^[0-9a-f-]{36}$/i.test(id)) return resp(400, { error: "Usuário inválido." });
    const { data: alvo } = await db.from("perfis").select("id").eq("id", id).maybeSingle();
    if (!alvo) return resp(404, { error: "Usuário não encontrado na Central." });
    const { error: updErr } = await admin.auth.admin.updateUserById(id, { password: senhaPadrao });
    if (updErr) return resp(500, { error: "Não foi possível redefinir a senha." });
    await db.from("perfis").update({ must_change_password: true }).eq("id", id);
    return resp(200, { ok: true });
  }

  return resp(400, { error: "Ação desconhecida." });
});
