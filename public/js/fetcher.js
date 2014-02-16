$.getJSON('http://pathtoyoursinatratwitterapp.com/tweets.json?callback=?').done(function(data) {
  $.each(data, function(index, value) {
    console.log(value); // Should output your tweet obj to inspect
    // Some DOM manipulation here ex: $('<li>').text(value.text);
  });
});