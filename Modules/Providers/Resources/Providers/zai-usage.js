function read(response) {
    const failure=message=>({error:{parseFailed:message}});
    const text=typeof response.text==='string'?response.text:(response.text==null?'':String(response.text));
    let json;
    try{json=JSON.parse(text);}catch(e){
        // Not JSON: a ZCode host log answers with its newest billing/balance
        // line; anything else keeps the old parse failure.
        const fromLog=balanceFromLog(text,failure);
        if(fromLog)return fromLog;
        return failure('Invalid JSON: '+e.message);
    }
    const object=v=>v && typeof v==='object' && !Array.isArray(v);
    if(!object(json) || (json.data!=null && !object(json.data)))return failure('Invalid JSON: Invalid quota response');
    const limits=json.data && json.data.limits;
    if(limits==null || (Array.isArray(limits)&&!limits.length))return failure('No quota limits found');
    if(!Array.isArray(limits))return failure('Invalid JSON: Invalid limits');
    const quotas=[];
    for(const entry of limits) {
        if(!object(entry)||typeof entry.type!=='string'||typeof entry.percentage!=='number'||!Number.isFinite(entry.percentage)||(entry.unit!=null && (!Number.isInteger(entry.unit)))||(entry.nextResetTime!=null && typeof entry.nextResetTime!=='string' && !Number.isInteger(entry.nextResetTime)))return failure('Invalid JSON: Invalid limit');
        // Only the units Z.ai documents state a window: 3 is 5 hours, 6 is a
        // week. Anything else states none, rather than a guessed week.
        let type,name,windowSeconds=null;
        if(entry.type==='TIME_LIMIT'){type='time';name='MCP';}
        else if(entry.type==='TOKENS_LIMIT'||entry.type==='CREDIT_LIMIT') {
            if(entry.unit==null||entry.unit===3){type='session';windowSeconds=18000;}
            else if(entry.unit===6){type='weekly';windowSeconds=604800;}
            else {type='model';name=entry.unit===7?'Monthly':(entry.type==='TOKENS_LIMIT'?'Tokens':'Credits')+' (unit '+entry.unit+')';}
        } else continue;
        let resetsAt=null;
        if(typeof entry.nextResetTime==='number')resetsAt=entry.nextResetTime/1000;
        else if(typeof entry.nextResetTime==='string') {
            const date=Date.parse(entry.nextResetTime);
            // Numeric strings are seconds, not milliseconds or calendar years.
            if(entry.nextResetTime.trim()!=='' && Number.isFinite(Number(entry.nextResetTime)))resetsAt=Number(entry.nextResetTime);
            else if(Number.isFinite(date))resetsAt=date/1000;
        }
        quotas.push({type,name,percentRemaining:100-Math.max(0,Math.min(100,entry.percentage)),resetsAt,windowSeconds});
    }
    return quotas.length?{quotas}:failure('No recognized quota types found');
}

function balanceFromLog(text,failure) {
    const lines=text.split('\n');
    let sawBalance=false;
    for(let i=lines.length-1;i>=0;i--){
        const marker=lines[i].indexOf('billing/balance');
        if(marker<0)continue;
        sawBalance=true;
        const brace=lines[i].indexOf('{',marker);
        if(brace<0)continue;
        let entry;
        try{entry=JSON.parse(lines[i].slice(brace));}catch(e){continue;}
        if(!entry||typeof entry!=='object'||Array.isArray(entry))continue;
        const data=entry.payload&&typeof entry.payload==='object'&&!Array.isArray(entry.payload)?entry.payload.data:null;
        const balances=(data&&Array.isArray(data.balances)?data.balances:null)||(Array.isArray(entry.balances)?entry.balances:null);
        const plans=(data&&Array.isArray(data.plans)?data.plans:null)||(Array.isArray(entry.plans)?entry.plans:null);
        const quotas=[];
        for(const balance of balances||[]) {
            if(!balance||typeof balance!=='object'||Array.isArray(balance))continue;
            const total=Number(balance.total_units);
            const remaining=Number(balance.remaining_units);
            if(!(total>0)||!Number.isFinite(remaining))continue;
            const percentRemaining=Math.max(0,Math.min(100,remaining/total*100));
            const expires=Number(balance.expires_at),end=Number(balance.period_end),start=Number(balance.period_start);
            const resetsAt=Number.isFinite(expires)?expires:(Number.isFinite(end)?end:null);
            const windowSeconds=Number.isFinite(start)&&Number.isFinite(end)&&end>start?end-start:null;
            if(quotas.length===0)quotas.push({type:'session',percentRemaining:percentRemaining,resetsAt:resetsAt,windowSeconds:windowSeconds});
            if(typeof balance.show_name==='string'&&balance.show_name!=='')
                quotas.push({type:'model',name:balance.show_name+' ('+formatUnits(remaining)+'/'+formatUnits(total)+')',percentRemaining:percentRemaining,resetsAt:resetsAt,windowSeconds:windowSeconds});
        }
        if(quotas.length)return {quotas:quotas,plan:plans&&plans[0]&&typeof plans[0].name==='string'&&plans[0].name!==''?plans[0].name:null};
    }
    return sawBalance?failure('No ZCode balance found in the log'):null;
}

function formatUnits(n) {
    const round=v=>{const s=v.toFixed(1);return s.slice(-2)==='.0'?s.slice(0,-2):s;};
    if(n>=1e9)return round(n/1e9)+'G';
    if(n>=1e6)return round(n/1e6)+'M';
    if(n>=1e3)return round(n/1e3)+'K';
    return String(Math.round(n));
}
