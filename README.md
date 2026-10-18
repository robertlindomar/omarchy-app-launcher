# Launcher Plus

Cópia independente do launcher personalizado de Robert, baseada no App Launcher de Tyrsolution.
Mantém a grade, favoritos, agentes e configurações em português. Ao digitar, troca a grade por uma lista com nomes e detalhes.
Sem IA, telemetria, sugestões web ou dependência do Spotlight instalado.

## Teste

- Super + Espaço: Launcher Plus.
- Ctrl + Alt + Espaço: launcher anterior, preservado.
- Busca normal: aplicativos, configurações, janelas e arquivos (a partir de dois caracteres).
- `f contrato`: somente arquivos e pastas; `f ~/Downloads/`: navegar por resultados daquela pasta.
- `ssh:`: listar hosts do SSH; `ssh: prod`: filtrar. Enter abre SSH no terminal; Shift+Enter copia o comando.
- `w: navegador`: somente janelas; `w:`: listar janelas.
- `cb: texto`: histórico de cópia do Omarchy, texto; `cb:`: itens recentes.
- `12*7+3`, `20% de 250`: cálculo offline; Enter copia o resultado.
- `5 km para m`, `72 f to c`: conversão de unidades offline.
- `gh quickshell`, `yt linux`, `web receita`: pesquisar na web somente após Enter.
- `https://example.com`: abrir endereço após Enter.
- ↑/↓: selecionar; Enter: abrir, focar janela ou copiar; Shift+Enter: abrir a pasta de um arquivo.
- Ctrl+F: favoritar aplicativos, agentes e hosts SSH; Esc: limpar, voltar a Todos, fechar.

A busca de arquivos respeita os arquivos de ignore e não pesquisa arquivos ocultos por padrão.
A pesquisa de arquivos tem limite de tempo e de resultados. O histórico consulta até 200 entradas de texto.
O histórico de cópia só é consultado com `cb:`; o conteúdo completo do item não entra no processo da shell.
Favoritos e histórico de uso iniciam com uma cópia do estado antigo e passam a ser independentes.

Esta adaptação incorpora os cinco recursos de busca combinados e conversões offline. Não inclui IA, câmbio online,
calendário, lembretes, prévias de arquivos ou painéis Docker do Spotlight.

## Voltar ao launcher anterior

Execute `bash /home/robert/cursorcli/backups/before-launcher-plus/restaurar.sh`.
A cópia anterior também pode ser aberta com Ctrl + Alt + Espaço.

## Créditos

Veja LICENSE e THIRD-PARTY.md. Calc.js e Units.js são do Spotlight de maajix, sob MIT.

SSH: lê aliases explícitos de ~/.ssh/config e Includes (com limite de arquivos e profundidade), além de known_hosts não criptografado. Ignora curingas e entradas com hash; não lê chaves privadas nem executa Match exec durante a busca. Includes condicionais são enumerados sem avaliar a condição.

Painel de detalhes: acompanha a seleção por teclado ou mouse, com ícone, descrição e metadados. Em telas menores que 1000 px lógicos, a coluna lateral fica oculta para preservar a navegação.

Hosts SSH podem ser favoritados com Ctrl+F ou botão direito. O favorito aparece na grade inicial e continua disponível mesmo oculto na busca. O menu permite ocultar só no launcher; `ssh:ocultos` lista os ocultos para restaurar. Abrir uma conexão por um favorito oculto restaura sua presença na busca. Conexões externas ao launcher não restauram a lista automaticamente; known_hosts permanece intacto.

Ctrl+O no host SSH selecionado alterna entre ocultar e restaurar, incluindo a lista ssh:ocultos.

Ctrl+Delete em um aplicativo abre uma confirmação com o tipo de remoção: atalho local, web app, pacote do sistema ou Flatpak. O menu de remoção usa a mesma confirmação. Componentes importantes reconhecidos, dependentes, transações extensas ou não verificadas exigem um segundo aviso. A seleção inicial é Cancelar; Tab/setas mudam a opção, Enter confirma e Esc cancela. A classificação é conservadora e não substitui a revisão da transação no terminal. Não remove arquivos nem conexões SSH por Ctrl+Delete.

Ctrl+Delete também funciona para agentes de código. A instalação é verificada: pacote do sistema ou ferramenta mise global. Para mise, remove a configuração global e instalações não usadas por outros projetos, desativa com backup o wrapper de reinstalação automática e preserva dados e sessões. A operação só é iniciada no terminal após as confirmações. Instalações não reconhecidas exibem o motivo sem apagar arquivos.

Ctrl+H abre/fecha o guia de três páginas: atalhos, buscas e SSH/remoção. Use Tab ou ←/→ para mudar de página e Esc para sair. Delete sozinho não inicia remoção; use Ctrl+Delete.

## Código e instalação

A versão personalizada está na branch `personal/launcher-plus` de https://github.com/robertlindomar/omarchy-app-launcher. Não depende da instalação do plugin Spotlight.

Clone a branch em `~/.config/omarchy/plugins/robertlindomar.launcher-plus`, execute `omarchy-shell shell rescanPlugins` e `omarchy plugin enable robertlindomar.launcher-plus`. Vincule o atalho ao comando `omarchy-shell shell toggle robertlindomar.launcher-plus '{}'`. Os nomes dos painéis de configurações usam os plugins pessoais em português.
