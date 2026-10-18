const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const s=fs.readFileSync(require('node:path').join(__dirname,'../AppGrid.qml'),'utf8');
function extract(name){const a=s.indexOf('  function '+name+'(');let i=s.indexOf('{',a)+1,n=1;for(;n&&i<s.length;i++){if(s[i]==='{')n++;if(s[i]==='}')n--;}return s.slice(a,i);}
let removals=[];
const root={removalStage:'',removalTarget:null,removalPlan:{},helper(args){return args;},removeDesktop(id){removals.push(id);},dismiss(){},};
let launches=[];
const ctx={Quickshell:{execDetached(args){launches.push(args);}},root,contextMenu:{hide(){}},keyCatcher:{forceActiveFocus(){}},removalDialog:{selectedIndex:1},removalInspector:{},Qt:{callLater(fn){fn();}}};
vm.createContext(ctx);vm.runInContext(['removeEntry','cancelRemoval','confirmRemoval'].map(extract).join('\n'),ctx);root.cancelRemoval=ctx.cancelRemoval;
for(const kind of ['ssh','file','clipboard'])ctx.removeEntry({id:'test',kind,name:'Test'});
assert.equal(root.removalStage,'');assert.equal(removals.length,0);
ctx.removeEntry({id:'test',kind:'app',name:'Test'});assert.equal(root.removalStage,'loading');
ctx.confirmRemoval();assert.equal(removals.length,0);
root.removalStage='first';root.removalPlan={canRemove:true,risky:true};ctx.confirmRemoval();
assert.equal(root.removalStage,'risk');assert.equal(removals.length,0);assert.equal(ctx.removalDialog.selectedIndex,0);
ctx.confirmRemoval();assert.equal(removals.length,1);ctx.confirmRemoval();assert.equal(removals.length,1);
ctx.removeEntry({id:'cancelled',kind:'app',name:'Cancel'});ctx.cancelRemoval();ctx.confirmRemoval();assert.equal(removals.length,1);
ctx.removeEntry({id:'ordinary',kind:'app',name:'Ordinary'});root.removalStage='first';root.removalPlan={canRemove:true,risky:false};ctx.confirmRemoval();assert.equal(removals[1],'ordinary');
console.log('Confirmação simples, aviso adicional, cancelamento e bloqueio de outros tipos: OK.');

ctx.removeEntry({id:'agent:opencode',kind:'agent',name:'OpenCode',argv:['opencode','--auto']});
assert.equal(ctx.removalInspector.command[0],'inspect-agent');
root.removalStage='first';root.removalPlan={canRemove:true,risky:true};ctx.confirmRemoval();assert.equal(launches.length,0);
ctx.confirmRemoval();assert.equal(launches.length,1);assert(launches[0].includes('uninstall-agent'));assert(launches[0].includes('opencode'));
console.log('Agente passa pelas duas confirmações antes de abrir a desinstalação: OK.');
