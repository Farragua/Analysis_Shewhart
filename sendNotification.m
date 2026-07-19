function [msg] = sendNotification(asset,data, entradas_2smm, entradas_2mmvix,vix,mm200);

today=length(data);

if entradas_2smm(end) == today 
msg = asset+ ":---2smm---:P="+data(today)+":MA200="+mm200+":VIX="+vix(end)+":"+date;

elseif entradas_2mmvix(end) == today 
msg = asset+ ":-2smm+VIX-:P="+data(today)+":MA200="+mm200+":VIX="+vix(end)+":"+date;

else
    msg = asset+ ":-NoSignal-:P="+data(today)+":MA200="+mm200+":VIX="+vix(end)+":"+date;

end
