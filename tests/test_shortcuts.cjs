const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const source=fs.readFileSync(require('node:path').join(__dirname,'../AppGrid.qml'),'utf8');
const a=source.indexOf('function(event)',source.indexOf('Keys.onPressed:'));let i=source.indexOf('{',a)+1,n=1;
for(;n&&i<source.length;i++){if(source[i]==='{')n++;if(source[i]==='}')n--;}
let removals=0,pages=0;
const root={removalStage:'',helpOpened:false,selectedRow(){return {kind:'app'};},removeEntry(){removals++;},toggleHelp(){this.helpOpened=!this.helpOpened;},changeHelpPage(){pages++;}};
const Qt={Key_Delete:127,Key_H:72,ControlModifier:1,AltModifier:2,ShiftModifier:4,NoModifier:0,Key_Escape:27,Key_Tab:9,Key_Right:1000};
const ctx={root,Qt,contextMenu:{visible:false}};vm.createContext(ctx);vm.runInContext('var handler='+source.slice(a,i),ctx);
ctx.handler({key:127,modifiers:0});assert.equal(removals,0);
ctx.handler({key:127,modifiers:1});assert.equal(removals,1);
ctx.handler({key:127,modifiers:3});assert.equal(removals,1);
ctx.handler({key:72,modifiers:1});assert.equal(root.helpOpened,true);
ctx.handler({key:127,modifiers:1});assert.equal(removals,1);
ctx.handler({key:9,modifiers:0});assert.equal(pages,1);
ctx.handler({key:27,modifiers:0});assert.equal(root.helpOpened,false);
console.log('Delete simples ignorado, Ctrl+Delete protegido, Ctrl+H e navegação da ajuda: OK.');
