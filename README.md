# Babel Chama — fila partilhada da equipa

Site estático com fila partilhada através do Supabase. O Cloudflare Workers publica os ficheiros da pasta `public` e pode fazer um novo deploy automaticamente quando recebe alterações do GitHub.

## Ficheiros

- `public/index.html`: aplicação.
- `public/config.js`: URL do Supabase e chave pública (anon/publishable).
- `public/team-photos/`: fotografias usadas pelo site.
- `supabase/setup.sql`: criação das tabelas, funções e rotina de limpeza diária.
- `wrangler.jsonc`: configuração do Worker `babel-chama-equipa`, com os assets na pasta `public`.

## Preparar o Supabase

Se ainda não executaste a configuração da base de dados, abre o SQL Editor do projeto Supabase, cola o conteúdo de `supabase/setup.sql` e executa. A chave `anon`/publishable em `public/config.js` é pública e necessária ao site; nunca coloques uma chave `service_role` neste projeto.

## GitHub e deploy automático

1. Cria um repositório **privado** no GitHub e coloca nele o conteúdo desta pasta, incluindo `wrangler.jsonc`, `package.json`, `public/` e `supabase/`.
2. No Cloudflare, abre **Workers & Pages → babel-chama-equipa → Settings → Builds → Connect** e liga esse repositório.
3. Define a raiz do projeto como a raiz do repositório (pasta `.`). O comando de deploy deve ser `npx wrangler deploy`; não é necessário comando de build.
4. Confirma que o nome do Worker é `babel-chama-equipa` e escolhe a branch principal (normalmente `main`).
5. Guarda a ligação e faz push de um commit. A cada push para a branch principal, o Cloudflare executará um novo deploy.
6. Em **Deployments**, confirma que o deploy ficou ativo e abre o endereço `workers.dev`.

A configuração `wrangler.jsonc` define `workers_dev: true` e publica os ficheiros de `public/` como assets estáticos.

## Importante sobre acesso

O site não pede autenticação. Quem tiver o endereço pode ver e alterar a fila; os nomes, fotografias e pedidos também são servidos publicamente. O repositório deve ficar privado, sobretudo por conter fotografias da equipa. A chave anon/publishable não é uma chave secreta, mas as permissões efetivas continuam definidas pelas políticas RLS e funções do SQL.

A rotina SQL tenta limpar a fila diariamente às 20h de Lisboa; confirma no Supabase que o SQL foi executado e que os jobs de Cron aparecem ativos.
