const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require('node:path').join(__dirname, '../AppGrid.qml'), 'utf8');
const start = source.indexOf('  function setSshHidden(');
const end = source.indexOf('\n  function persistUsage()', start);
function scenario(count, index, scroll, hiddenView = false) {
  const rows = Array.from({length: count}, (_, i) => ({id: 'ssh:host'+i, kind:'ssh'}));
  const callbacks=[];
  const grid={contentY:scroll, contentHeight:count*56, height:224, forceLayout(){}};
  const root={searchRows:rows, allRows:rows, hiddenSsh:hiddenView ? Object.fromEntries(rows.map(r=>[r.id,true])) : {},
    selectedSection:'all', selectedIndex:index, filterText:hiddenView?'ssh:ocultos':'ssh:',
    showingHiddenSsh:hiddenView, opened:true,
    startSearch(){throw Error('Não deve reiniciar a busca');},
    rebuild(){this.allRows=this.searchRows;grid.contentY=0;grid.contentHeight=this.allRows.length*56;},
    rowsFor(){return this.allRows;},select(section,index){this.selectedSection=section;this.selectedIndex=index;}};
  const ctx={root,allGrid:grid,hiddenSshFile:{setText(){}},Qt:{callLater(fn){callbacks.push(fn);}}};
  vm.createContext(ctx);vm.runInContext(source.slice(start,end),ctx);
  ctx.setSshHidden(rows[index],!hiddenView);callbacks.forEach(fn=>fn());
  assert.equal(root.allRows.length,count-1);
  assert.equal(root.selectedIndex,Math.max(0,Math.min(index,count-2)));
  assert.equal(grid.contentY,Math.max(0,Math.min(scroll,(count-1)*56-224)));
  assert.equal(root.adjustingRows,false);
}
scenario(14,9,280);
scenario(14,13,560);
scenario(1,0,0);
scenario(14,9,280,true);
console.log('Ocultar/restaurar preserva seleção e rolagem, inclusive último item: OK.');
