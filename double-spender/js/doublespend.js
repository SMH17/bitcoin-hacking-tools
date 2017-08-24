jQuery(function($){
	$(function() {
	  // Setup drop down menu
	  $('.dropdown-toggle').dropdown();
	 
	  // Fix input element click problem
	  $('.dropdown input, .dropdown label').click(function(e) {
		e.stopPropagation();
	  });
	});
	$(document).ready(function(){
		var privatekey;
		var publickey;
		var keytimer;
		var brainwallet = false;
		var minfee = parseFloat($('#minfee').val());
		var maxfee = parseFloat($('#maxfee').val());
		$('#key').keyup(function(){
			clearTimeout(keytimer);
			$('#brainwallet').hide();
			$('#key').closest('.form-group').removeClass('has-error');
			var value = $(this).val();
			if(value != ''){
				var keytimer = setTimeout(function(){
					var decode = coinjs.addressDecode(value);
			
					if(decode.version == coinjs.pub){
						error('You must enter the private key, not the address',$('#key'));
					} else if (decode.version == coinjs.priv){
						var a = coinjs.wif2address(value);
						publickey = a['address'];
						privatekey = value;
						$('#address span').text(publickey);
						$('#address').show();
						loadBalance();
						return;
					} else if (decode.version == coinjs.multisig){
						error('Sorry cannot spend from multisig',$('#key'));
					} else {
						if(brainwallet){
							coinjs.compressed = false;
							var coin = coinjs.newKeys(value);
							publickey = coin.address;
							privatekey = coin.wif;
							$('#address span').text(publickey);
							$('#address').show();
							loadBalance();
							return;
						}else{
							$('#brainwallet').show();
						}
						// Input is something else; do nothing
					}
					$('#address').hide();


				},500);
			}
		}).change(function(){$(this).trigger('keyup')}).trigger('keyup');
		
		$('#brainwallet button').click(function(){
			brainwallet = true;
			$('#key').trigger('keyup');
		});
		
		var loadajax = false;
		var inputs;
		var balance = 0;
		function loadBalance(){
			balance = 0;
			$('#balance').html('<i class="fa fa-refresh fa-spin"></i> Loading');
			if(loadajax && loadajax.readystate != 4){
				loadajax.abort();
			}
			
			loadajax = $.getJSON("https://btc.blockr.io/api/v1/address/unspent/"+publickey+'/?callback=?',function(rec){
				inputs = rec.data.unspent;
				$.each(inputs, function(i, v){
					balance += parseFloat(v.amount);
				});
				$('#balance').html(balance.toFixed(8)+ ' Available');
			});
			
		}
		
		$('#balance').click(function(){loadBalance();});
		
		function error(str, el){
			var p = $(el).closest('.form-group');
			$('.alert',p).remove();
			$(p).addClass('has-error').prepend('<div class="alert alert-danger">'+str+'</div>');
		}
		
		
		$('#generate').submit(function(){
			if(balance > 0){
				var amount = parseFloat($('#amount').val());
				if(isNaN(amount) || amount <= 0){
					error('Invalid amount','#amount');
					return false;
				}
				if(amount + maxfee > balance){
					error('Max amount is: '+(balance-maxfee).toFixed(8)+' BTC','#amount');
					return false;
				}
				
				var decode = coinjs.addressDecode($('#sendto').val());
				if(!decode || (decode.version != coinjs.pub && decode.version != coinjs.multisig)){
					error('You entered an invalid address to send to','#sendto');
					return false;
				}
				
				var change = publickey;
				if($('#change').val() != ''){
					change = $('#change').val();
					decode = coinjs.addressDecode(change);
					if(!decode || (decode.version != coinjs.pub && decode.version != coinjs.multisig)){
						error('You entered an invalid change address','#change');
						return false;
					}
				}
				
				inputs.sort(function(x, y){ 
					if (y.amount < x.amount) {
						return -1;
					}
					if (y.amount > x.amount) {
						return 1;
					}
					return 0;
				});
				
				var a = 0;
				coinjs.compressed = true;
				var tx = coinjs.transaction();
				var tx2 = coinjs.transaction();
				
				$.each(inputs, function(i,v){
					if(a < (amount + maxfee)){
						tx.addinput(v.tx, v.n, v.script);
						tx2.addinput(v.tx, v.n, v.script);
						a += v.amount;
					}
				});
				
				tx.addoutput($('#sendto').val(), amount);
				tx2.addoutput(change, a - maxfee);
				
				changeamt = a - amount - minfee;
				if(changeamt > 0){
					tx.addoutput(change, changeamt);
				}
				
				var txunspent1 = tx.deserialize(tx.serialize()); 
				var txunspent2 = tx.deserialize(tx2.serialize()); 

				// then sign
				$('#tx1 textarea').val(txunspent1.sign(privatekey));
				$('#tx2 textarea').val(txunspent2.sign(privatekey));
				$('#tx1, #tx2').show();
			}else{
				error('Balance is zero','#amount');
			}
			return false;
		});
	});
});