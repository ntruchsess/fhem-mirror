var fd_loadedHash={}, fd_loadedList=[], fd_all={}, fd_allCnt, fd_progress=0, 
    fd_lang, fd_offsets=[], fd_scrolled=0, fd_modLinks={};


function
fd_status(txt)
{
  var errmsg = $("#errmsg");
  if(!$(errmsg).length) {
    $('#menuScrollArea').append('<div id="errmsg">');
    errmsg = $("#errmsg");
  }
  if(txt == "")
    $(errmsg).remove();
  else
    $(errmsg).html(txt);
}

function
fd_fC(fn, callback)
{
  var p = location.pathname;
  var cmd = p.substr(0,p.indexOf('/doc'))+
                '?cmd='+fn+
                (typeof(csrfToken)!='undefined'?csrfToken:'')+
                '&XHR=1';
  var ax = $.ajax({ cache:false, url:cmd });
  ax.done(callback);
  ax.fail(function(req, stat, err) {
    console.log("FAIL ERR:"+err+" STAT:"+stat);
  });
}

function
loadOneDoc(mname, lang)
{
  var origLink = mname;

  function
  done(err, calc)
  {
    if(fd_progress) {
      fd_status(fd_progress+" / "+fd_allCnt);
      if(++fd_progress > fd_allCnt) {
        fd_progress = 0;
        setTimeout(calcOffsets,100);   // Firefox returns wrong offsets
        fd_status("");
      }
    } else {
      if(calc)
        setTimeout(calcOffsets,100);
      if(!err)
        setTimeout(function(){location.href = "#"+origLink;}, 100);
    }
  }

  if(fd_modLinks[mname])
    mname = fd_modLinks[mname];
  if(fd_loadedHash[mname] && fd_loadedHash[mname] == lang)
    return done(false, false);

  fd_fC("help "+mname+" "+lang, function(ret){
    //console.log(mname+" "+lang+" => "+ret.length);
    if(ret.indexOf("<html>") != 0 || ret.indexOf("<html>No help found") == 0)
      return done(true, false);
    ret = ret.replace(/<\/?html>/g,'');
    ret = ret.replace(/Keine deutsche Hilfe gefunden!<br\/>/,'');
    ret = '<div id="FD_'+mname+'">'+ret+'</div>';
    ret = ret.replace(/target="_blank"/g, '');  // revert help URL rewrite
    ret = ret.replace(/href=".*commandref.*.html#/g, 'href="#');

    if(fd_loadedHash[mname])
      $("div#FD_"+mname).remove();

    if(!fd_loadedHash[mname])
      fd_loadedList.push(mname);
    fd_loadedHash[mname] = lang;
    fd_loadedList.sort();
    var idx=0;
    while(fd_loadedList[idx] != mname)
      idx++;
    var toIns = "perl";
    if(idx < fd_loadedList.length-1)
      toIns = fd_loadedList[idx+1];
    console.log("insert "+mname+" before "+toIns);
    $(ret).insertBefore("a[name="+toIns+"]");
    addAHooks("div#FD_"+mname);
    return done(false, true);
  });
}

function
addAHooks(el)
{
  $(el).find("a[href]").each(function(){
    var href = $(this).attr("href");
    if(!href || href.indexOf("#") != 0)
      return;
    href = href.substr(1);
    if(fd_modLinks[href] && !fd_loadedHash[href]) {
      $(this).click(function(){
        $("a[href=#"+href+"]").unbind('click');
        loadOneDoc(href, fd_lang);
      });
    }
  });
}

function
calcOffsets()
{
  fd_offsets=[];
  for(var i1=0; i1<fd_loadedList.length; i1++) {
    var cr = $("a[name="+fd_loadedList[i1]+"]").offset();
    fd_offsets.push(cr ? cr.top : -1);
  }
  checkScroll();
}

function
checkScroll()
{
  if(!fd_scrolled) {
    setTimeout(checkScroll, 500);
    return;
  }
  fd_scrolled = 0;
  var viewTop=$(window).scrollTop(), viewBottom=viewTop+$(window).height();
  var idx=0;
  while(idx<fd_offsets.length) {
    if(fd_offsets[idx] >= viewTop && viewBottom > fd_offsets[idx]+30)
      break;
    idx++;
  }

  if(idx >= fd_offsets.length) {
    $("a#otherLang").hide();

  } else {
    var mname = fd_loadedList[idx];
    var l1 = fd_loadedHash[mname], l2 = (l1=="EN" ? "DE" : "EN");
    $("a#otherLang span.mod").html(mname);
    $("a#otherLang span[lang="+l1+"]").hide();
    $("a#otherLang span[lang="+l2+"]").show();
    $("a#otherLang").show();
  }
}

function
loadOtherLang()
{
  var mname = $("a#otherLang span.mod").html();
  loadOneDoc(mname, fd_loadedHash[mname]=="EN" ? "DE" : "EN");
}

$(document).ready(function(){
  var p = location.pathname;
  fd_lang = p.substring(p.indexOf("commandref")+11,p.indexOf(".html"));
  if(!fd_lang || fd_lang == '.')
    fd_lang = "EN";

  $("div#modLinks").each(function(){
    var a1 = $(this).html().split(" ");
    for(var i1=0; i1<a1.length; i1++) {
      var a2 = a1[i1].split(/[:,]/);
      var mName = a2.shift();
      for(var i2=0; i2<a2.length; i2++)
        if(!fd_modLinks[a2[i2]])
          fd_modLinks[a2[i2]] = mName;
    }
  });

  $("a[name]").each(function(){ fd_loadedHash[$(this).attr("name")]=fd_lang; });
  $("table.summary td.modname a")
    .each(function(){ 
      var mod = $(this).html();
      fd_all[mod]=1;
      fd_modLinks[mod] = fd_modLinks[mod+"define"] = fd_modLinks[mod+"get"] = 
      fd_modLinks[mod+"set"] = fd_modLinks[mod+"attribute"]= mod;
    })
    .click(function(e){
      e.preventDefault();
      loadOneDoc($(this).html(), fd_lang);
    });

  if(location.hash)
    loadOneDoc(location.hash.substr(1), fd_lang);

  $("a[name=loadAll]").show().click(function(e){
    e.preventDefault();
    $("a[name=loadAll]").hide();
    location.href = "#doctop";
    fd_allCnt = 0;
    for(var m in fd_all) fd_allCnt++
    fd_progress = 1;
    for(var mname in fd_all)
      loadOneDoc(mname, fd_lang);
  });

  $("a#otherLang").click(loadOtherLang);
  addAHooks("body");

  window.onscroll = function(){ 
    if(!fd_scrolled++)
      setTimeout(checkScroll, 500);
  };
});
