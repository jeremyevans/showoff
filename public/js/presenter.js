// presenter js
var slaveWindow = null;

var paceData = [];

$(document).ready(function(){
  // the presenter window doesn't need the reload on resize bit
  $(window).unbind('resize');

  // side menu accordian crap
	$("#preso").bind("showoff:loaded", function (event) {
		$(".menu > ul ul").hide()
		$(".menu > ul a").click(function() {
			if ($(this).next().is('ul')) {
				$(this).next().toggle()
			} else {
				gotoSlide($(this).attr('rel'));
				try { slaveWindow.gotoSlide($(this).attr('rel'), false) } catch (e) {}
				postSlide();
			}
			return false;
		}).next().hide();
    postSlide();
	});

  $("#minStop").hide();

  /* zoom slide to match preview size, then set up resize handler. */
  zoom();
  $(window).resize(function() { zoom(); });

  // Bind events for mobile viewing
  $('#preso').unbind('tap').unbind('swipeleft').unbind('swiperight');

  $('#preso').addSwipeEvents().
    bind('tap', presNextStep).        // next
    bind('swipeleft', presNextStep).  // next
    bind('swiperight', presPrevStep); // prev

  $('#topbar #update').click( function(e) {
    e.preventDefault();
    $.get("/getpage", function(data) {
      gotoSlide(data);
    });
  });
	postSlide();
});

function toggleSlave() {
  slaveMode = !slaveMode;
  openSlave();
}

function openSlave()
{
  if (slaveMode) {
    try {
      if(slaveWindow == null || typeof(slaveWindow) == 'undefined' || slaveWindow.closed){
          slaveWindow = window.open('index.html' + window.location.hash, 'toolbar');
      }
      else if(slaveWindow.location.hash != window.location.hash) {
        // maybe we need to reset content?
        slaveWindow.location.href = 'index.html' + window.location.hash;
      }

      // maintain the pointer back to the parent.
      slaveWindow.presenterView = window;
      slaveWindow.slaveMode = true;

      $('#slaveWindow').addClass('enabled');
    }
    catch(e) {
      console.log('Failed to open or connect slave window. Popup blocker?');
    }

    // Set up a maintenance loop to keep the connection between windows. I wish there were a cleaner way to do this.
    if (typeof maintainSlave == 'undefined') {
      maintainSlave = setInterval(openSlave, 1000);
    }
  }
  else {
    try {
      slaveWindow && slaveWindow.close();
      $('#slaveWindow').removeClass('enabled');
    }
    catch (e) {
      console.log('Slave window failed to close properly.');
    }
  }
}

function zoom()
{
  if(window.innerWidth <= 480) {
    $(".zoomed").css("zoom", 0.32);
  }
  else {
    var hSlide = parseFloat($("#preso").height());
    var wSlide = parseFloat($("#preso").width());
    var hPreview = parseFloat($("#preview").height());
    var wPreview = parseFloat($("#preview").width());
    var factor = parseFloat($("#zoomer").val());

    n =  Math.min(hPreview/hSlide, wPreview/wSlide) - 0.04;

    $(".zoomed").css("zoom", n*factor);
  }
}

// extend this function to add presenter bits
var origGotoSlide = gotoSlide;
gotoSlide = function (slideNum)
{
    origGotoSlide.call(this, slideNum)
    try { slaveWindow.gotoSlide(slideNum, false) } catch (e) {}
    postSlide()
}

function presPrevStep()
{
    prevStep();
    try { slaveWindow.prevStep(false) } catch (e) {};
    postSlide();
}

function presNextStep()
{
	nextStep();
	try { slaveWindow.nextStep(false) } catch (e) {};
	postSlide();
}

function postSlide()
{
	if(currentSlide) {
    var notes = getCurrentNotesText()
    $('#notes').html(notes)

		var fileName = currentSlide.children().first().attr('ref')
		$('#slideFile').text(fileName)
	}
}

//  See e.g. http://www.quirksmode.org/js/keys.html for keycodes
function keyDown(event)
{
	var key = event.keyCode;

	if (event.ctrlKey || event.altKey || event.metaKey)
		return true;

	debug('keyDown: ' + key)

	if (key >= 48 && key <= 57) // 0 - 9
	{
		gotoSlidenum = gotoSlidenum * 10 + (key - 48);
		return true;
	}

	if (key == 13) {
    if (gotoSlidenum > 0) {
      debug('go to ' + gotoSlidenum);
      slidenum = gotoSlidenum - 1;
      showSlide(true);
      try {
        slaveWindow.slidenum = gotoSlidenum - 1;
        slaveWindow.showSlide(true);
      } catch (e) {}
        gotoSlidenum = 0;
    } else {
      debug('executeCode');
      executeAnyCode();
      try { slaveWindow.executeAnyCode(); } catch (e) {}
    }
	}

	if (key == 16) // shift key
	{
		shiftKeyActive = true;
	}

	if (key == 32) // space bar
	{
		if (shiftKeyActive) {
			presPrevStep()
		} else {
			presNextStep()
		}
	}
	else if (key == 68) // 'd' for debug
	{
		debugMode = !debugMode
		doDebugStuff()
	}
	else if (key == 37 || key == 33 || key == 38) // Left arrow, page up, or up arrow
	{
		presPrevStep();
	}
	else if (key == 39 || key == 34 || key == 40) // Right arrow, page down, or down arrow
	{
		presNextStep();
	}
	else if (key == 84 || key == 67)  // T or C for table of contents
	{
		$('#navmenu').toggle().trigger('click')
	}
	else if (key == 83)  // 's' for style
	{
		$('#stylemenu').toggle().trigger('click')
	}
	else if (key == 90 || key == 191) // z or ? for help
	{
		$('#help').toggle()
	}
	else if (key == 66 || key == 70) // f for footer (also "b" which is what kensington remote "stop" button sends
	{
		toggleFooter()
	}
	else if (key == 78) // 'n' for notes
	{
		toggleNotes()
	}
	else if (key == 27) // esc
	{
		removeResults();
		try { slaveWindow.removeResults(); } catch (e) {}
	}
	else if (key == 80) // 'p' for preshow
	{
		try { slaveWindow.togglePreShow(); } catch (e) {}
	}
	return true
}

var presSetCurrentStyle = setCurrentStyle;
var setCurrentStyle = function(style, prop) {
  presSetCurrentStyle(style, false);
  try { slaveWindow.setCurrentStyle(style, false); } catch (e) {}
}

function mobile() {
  return ( navigator.userAgent.match(/Android/i)
            || navigator.userAgent.match(/webOS/i)
            || navigator.userAgent.match(/iPhone/i)
            || navigator.userAgent.match(/iPad/i)
            || navigator.userAgent.match(/iPod/i)
            || navigator.userAgent.match(/BlackBerry/i)
            || navigator.userAgent.match(/Windows Phone/i)
  );
}
