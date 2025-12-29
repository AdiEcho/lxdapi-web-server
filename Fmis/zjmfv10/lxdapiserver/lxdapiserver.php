<?php

use app\common\model\HostModel;

function lxdapiserver_MetaData(){
	return [
		'DisplayName' => '魔方财务V10-LXD对接插件 by xkatld',
		'Version' => 'v2.0.3',
		'HelpDoc' => 'https://github.com/xkatld/lxdapi-web-server',
	];
}

function lxdapiserver_ConfigOptions(){
	return [
		[
			'type'=>'text', 
			'name'=>'CPU核心数', 
			'key'=>'cpus'
		],
		[
			'type'=>'text', 
			'name'=>'内存(MB)', 
			'key'=>'memory'
		],
		[
			'type'=>'text', 
			'name'=>'硬盘(MB)', 
			'key'=>'disk'
		],
		[
			'type'=>'text', 
			'name'=>'系统镜像', 
			'key'=>'image'
		],
		[
			'type'=>'text', 
			'name'=>'入站带宽(Mbit)', 
			'key'=>'ingress'
		],
		[
			'type'=>'text', 
			'name'=>'出站带宽(Mbit)', 
			'key'=>'egress'
		],
		[
			'type'=>'text', 
			'name'=>'月流量限制(GB)', 
			'key'=>'traffic_limit'
		],
		[
			'type'=>'text', 
			'name'=>'IPv4地址池', 
			'key'=>'ipv4_pool_limit'
		],
		[
			'type'=>'text', 
			'name'=>'IPv4端口映射', 
			'key'=>'ipv4_mapping_limit'
		],
		[
			'type'=>'text', 
			'name'=>'IPv6地址池', 
			'key'=>'ipv6_pool_limit'
		],
		[
			'type'=>'text', 
			'name'=>'IPv6端口映射', 
			'key'=>'ipv6_mapping_limit'
		],
		[
			'type'=>'text', 
			'name'=>'反向代理数', 
			'key'=>'reverse_proxy_limit'
		],
		[
			'type'=>'text', 
			'name'=>'CPU限制(%)', 
			'key'=>'cpu_allowance'
		],
		[
			'type'=>'text', 
			'name'=>'磁盘读取(MB/s)', 
			'key'=>'io_read'
		],
		[
			'type'=>'text', 
			'name'=>'磁盘写入(MB/s)', 
			'key'=>'io_write'
		],
		[
			'type'=>'text', 
			'name'=>'最大进程数', 
			'key'=>'processes_limit'
		],
		[
			'type'=>'yesno', 
			'name'=>'嵌套虚拟化', 
			'key'=>'allow_nesting'
		],
		[
			'type'=>'yesno', 
			'name'=>'Swap开关', 
			'key'=>'memory_swap'
		],
		[
			'type'=>'yesno', 
			'name'=>'特权模式', 
			'key'=>'privileged'
		],
	];
}

function lxdapiserver_GetContainerName($params){
	if(isset($params['domain']) && !empty($params['domain'])){
		return is_array($params['domain']) ? ($params['domain'][0] ?? '') : $params['domain'];
	}
	if(isset($params['hostid'])){
		try {
			$host = HostModel::find($params['hostid']);
			if($host && !empty($host['name'])){
				return $host['name'];
			}
		} catch (\Exception $e) {}
	}
	return '';
}

function lxdapiserver_TestLink($params){
	$res = lxdapiserver_Curl($params, '/api/system/containers', [], 'GET');
	if(isset($res['code']) && $res['code'] == 200){
		$result['status'] = 200;
		$result['data']['server_status'] = 1;
	}else{
		$result['status'] = 200;
		$result['data']['server_status'] = 0;
		$result['data']['msg'] = $res['msg'] ?? '连接失败';
	}
	return $result;
}

function lxdapiserver_CreateAccount($params){
	$domain = $params['domain'] ?? '';
	$containerName = is_array($domain) ? ($domain[0] ?? '') : $domain;
	if(empty($containerName)){
		$containerName = 'lxd' . rand(1000,9999) . $params['hostid'];
	}
	
	$configoptions = $params['configoptions'] ?? [];
	$post_data = [
		'name' => $containerName,
		'image' => $configoptions['image'] ?? 'alpine320',
		'username' => 'user_' . $params['uid'],
		'password' => $params['password'] ?: substr(md5(uniqid()), 0, 12),
		'cpu' => (int)($configoptions['cpus'] ?? 1),
		'memory' => (int)($configoptions['memory'] ?? 512),
		'disk' => (int)($configoptions['disk'] ?? 1024),
		'ingress' => (int)($configoptions['ingress'] ?? 100),
		'egress' => (int)($configoptions['egress'] ?? 100),
		'traffic_limit' => (int)($configoptions['traffic_limit'] ?? 100),
		'allow_nesting' => ($configoptions['allow_nesting'] ?? 1) == 1,
		'memory_swap' => ($configoptions['memory_swap'] ?? 1) == 1,
		'privileged' => ($configoptions['privileged'] ?? 0) == 1,
		'cpu_allowance' => (int)($configoptions['cpu_allowance'] ?? 50),
		'io_read' => (int)($configoptions['io_read'] ?? 100),
		'io_write' => (int)($configoptions['io_write'] ?? 50),
		'processes_limit' => (int)($configoptions['processes_limit'] ?? 512),
		'ipv4_pool_limit' => (int)($configoptions['ipv4_pool_limit'] ?? 0),
		'ipv4_mapping_limit' => (int)($configoptions['ipv4_mapping_limit'] ?? 0),
		'ipv6_pool_limit' => (int)($configoptions['ipv6_pool_limit'] ?? 0),
		'ipv6_mapping_limit' => (int)($configoptions['ipv6_mapping_limit'] ?? 0),
		'reverse_proxy_limit' => (int)($configoptions['reverse_proxy_limit'] ?? 0),
	];
	
	$res = lxdapiserver_Curl($params, '/api/system/containers', $post_data, 'POST');
	
	if(isset($res['code']) && $res['code'] == 200){
		try {
			$HostModel = new HostModel();
			$HostModel->where('id', $params['hostid'])->update([
				'name' => $containerName,
				'status' => 'Active'
			]);
		} catch (\Exception $e) {}
		return 'ok';
	}else{
		return ['status'=>'error', 'msg'=>$res['msg'] ?? '创建失败'];
	}
}

function lxdapiserver_TerminateAccount($params){
	$containerName = lxdapiserver_GetContainerName($params);
	$res = lxdapiserver_Curl($params, '/api/system/containers/' . urlencode($containerName), [], 'DELETE');
	if(isset($res['code']) && $res['code'] == 200){
		return ['status'=>'success', 'msg'=>$res['msg'] ?? '删除成功'];
	}else{
		return ['status'=>'error', 'msg'=>$res['msg'] ?? '删除失败'];
	}
}

function lxdapiserver_SuspendAccount($params){
	$containerName = lxdapiserver_GetContainerName($params);
	$res = lxdapiserver_Curl($params, '/api/system/containers/' . urlencode($containerName) . '/action?action=stop', [], 'POST');
	if(isset($res['code']) && $res['code'] == 200){
		return ['status'=>'success', 'msg'=>$res['msg'] ?? '暂停成功'];
	}else{
		return ['status'=>'error', 'msg'=>$res['msg'] ?? '暂停失败'];
	}
}

function lxdapiserver_UnsuspendAccount($params){
	$containerName = lxdapiserver_GetContainerName($params);
	$res = lxdapiserver_Curl($params, '/api/system/containers/' . urlencode($containerName) . '/action?action=start', [], 'POST');
	if(isset($res['code']) && $res['code'] == 200){
		return ['status'=>'success', 'msg'=>$res['msg'] ?? '恢复成功'];
	}else{
		return ['status'=>'error', 'msg'=>$res['msg'] ?? '恢复失败'];
	}
}

function lxdapiserver_On($params){
	$containerName = lxdapiserver_GetContainerName($params);
	$res = lxdapiserver_Curl($params, '/api/system/containers/' . urlencode($containerName) . '/action?action=start', [], 'POST');
	if(isset($res['code']) && $res['code'] == 200){
		return ['status'=>'success', 'msg'=>$res['msg'] ?? '开机成功'];
	}else{
		return ['status'=>'error', 'msg'=>$res['msg'] ?? '开机失败'];
	}
}

function lxdapiserver_Off($params){
	$containerName = lxdapiserver_GetContainerName($params);
	$res = lxdapiserver_Curl($params, '/api/system/containers/' . urlencode($containerName) . '/action?action=stop', [], 'POST');
	if(isset($res['code']) && $res['code'] == 200){
		return ['status'=>'success', 'msg'=>$res['msg'] ?? '关机成功'];
	}else{
		return ['status'=>'error', 'msg'=>$res['msg'] ?? '关机失败'];
	}
}

function lxdapiserver_Reboot($params){
	$containerName = lxdapiserver_GetContainerName($params);
	$res = lxdapiserver_Curl($params, '/api/system/containers/' . urlencode($containerName) . '/action?action=restart', [], 'POST');
	if(isset($res['code']) && $res['code'] == 200){
		return ['status'=>'success', 'msg'=>$res['msg'] ?? '重启成功'];
	}else{
		return ['status'=>'error', 'msg'=>$res['msg'] ?? '重启失败'];
	}
}

function lxdapiserver_Reinstall($params){
	$containerName = lxdapiserver_GetContainerName($params);
	if(empty($params['reinstall_os'])){
		return ['status'=>'error', 'msg'=>'镜像参数错误'];
	}
	$post_data = [
		'image' => $params['reinstall_os'],
		'password' => $params['password'] ?: substr(md5(uniqid()), 0, 12),
	];
	$res = lxdapiserver_Curl($params, '/api/system/containers/' . urlencode($containerName) . '/action?action=reinstall', $post_data, 'POST');
	if(isset($res['code']) && $res['code'] == 200){
		return ['status'=>'success', 'msg'=>$res['msg'] ?? '重装成功'];
	}else{
		return ['status'=>'error', 'msg'=>$res['msg'] ?? '重装失败'];
	}
}

function lxdapiserver_CrackPassword($params, $new_pass){
	$containerName = lxdapiserver_GetContainerName($params);
	$res = lxdapiserver_Curl($params, '/api/system/containers/' . urlencode($containerName) . '/action?action=reset-password', ['password'=>$new_pass], 'POST');
	if(isset($res['code']) && $res['code'] == 200){
		return ['status'=>'success', 'msg'=>$res['msg'] ?? '密码重置成功'];
	}else{
		return ['status'=>'error', 'msg'=>$res['msg'] ?? '密码重置失败'];
	}
}

function lxdapiserver_Status($params){
	$containerName = lxdapiserver_GetContainerName($params);
	$res = lxdapiserver_Curl($params, '/api/system/containers/' . urlencode($containerName), [], 'GET');
	if(isset($res['code']) && $res['code'] == 200 && isset($res['data']['status'])){
		$status = strtoupper($res['data']['status']);
		if($status == 'RUNNING'){
			return ['status'=>'success', 'data'=>['status'=>'on', 'des'=>'运行中']];
		}elseif($status == 'STOPPED'){
			return ['status'=>'success', 'data'=>['status'=>'off', 'des'=>'已停止']];
		}else{
			return ['status'=>'success', 'data'=>['status'=>'unknown', 'des'=>'未知']];
		}
	}else{
		return ['status'=>'error', 'msg'=>$res['msg'] ?? '查询失败'];
	}
}

function lxdapiserver_Vnc($params){
	$containerName = lxdapiserver_GetContainerName($params);
	$res = lxdapiserver_Curl($params, '/api/system/console/create-token', ['hostname'=>$containerName], 'POST');
	if(isset($res['code']) && $res['code'] == 200 && isset($res['data']['token'])){
		$url = 'https://' . $params['server_ip'] . ':' . $params['port'] . '/console?token=' . $res['data']['token'];
		return ['status'=>'success', 'url'=>$url];
	}else{
		return ['status'=>'error', 'msg'=>$res['msg'] ?? 'VNC连接失败'];
	}
}

function lxdapiserver_ClientArea($params){
	return [
		'info'=>[
			'name'=>'容器信息',
		],
	];
}

function lxdapiserver_ClientAreaOutput($params, $key){
	if($key == 'info'){
		$containerName = lxdapiserver_GetContainerName($params);
		$res = lxdapiserver_Curl($params, '/api/system/containers/' . urlencode($containerName) . '/credential', [], 'GET');
		
		$jumpUrl = '';
		$iframeUrl = '';
		$errorMsg = '';
		
		if(isset($res['code']) && $res['code'] == 200 && isset($res['data']['access_code'])){
			$accessCode = $res['data']['access_code'];
			$baseUrl = 'https://' . $params['server_ip'] . ':' . $params['port'];
			$jumpUrl = $baseUrl . '/container/dashboard?hash=' . $accessCode;
			$iframeUrl = $baseUrl . '/container/dashboard/base?hash=' . $accessCode;
		}else{
			$errorMsg = $res['msg'] ?? '获取访问码失败';
		}
		
		return [
			'template'=>'templates/info.html',
			'vars'=>[
				'container_name'=>$containerName,
				'jump_url'=>$jumpUrl,
				'iframe_url'=>$iframeUrl,
				'error_msg'=>$errorMsg,
			]
		];
	}
	return '';
}

function lxdapiserver_Curl($params, $path, $data = [], $method = 'POST'){
	$url = 'https://' . $params['server_ip'] . ':' . $params['port'] . $path;
	$apiHash = $params['accesshash'] ?? $params['server_password'] ?? '';
	
	$curl = curl_init();
	curl_setopt($curl, CURLOPT_URL, $url);
	curl_setopt($curl, CURLOPT_TIMEOUT, 30);
	curl_setopt($curl, CURLOPT_RETURNTRANSFER, 1);
	curl_setopt($curl, CURLOPT_SSL_VERIFYPEER, false);
	curl_setopt($curl, CURLOPT_SSL_VERIFYHOST, false);
	curl_setopt($curl, CURLOPT_HTTPHEADER, [
		'X-API-Hash: ' . $apiHash,
		'Content-Type: application/json'
	]);
	
	if($method == 'POST'){
		curl_setopt($curl, CURLOPT_POST, 1);
		curl_setopt($curl, CURLOPT_POSTFIELDS, json_encode($data));
	}elseif($method == 'DELETE'){
		curl_setopt($curl, CURLOPT_CUSTOMREQUEST, 'DELETE');
	}elseif($method == 'PUT'){
		curl_setopt($curl, CURLOPT_CUSTOMREQUEST, 'PUT');
		curl_setopt($curl, CURLOPT_POSTFIELDS, json_encode($data));
	}
	
	$response = curl_exec($curl);
	curl_close($curl);
	
	return json_decode($response, true) ?: [];
}
