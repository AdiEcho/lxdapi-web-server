<?php

use think\Db;

function lxdwebserver_MetaData()
{
    return [
        'DisplayName' => '魔方财务-LXD用户对接插件 by xkatld',
        'APIVersion'  => 'v2.0.5',
        'HelpDoc'     => 'https://github.com/xkatld/lxdapi-web-server',
    ];
}

function lxdwebserver_ConfigOptions()
{
    return [
        'cpu_limit' => [
            'type'        => 'text',
            'name'        => 'CPU总配额',
            'description' => '可用CPU配额，单位：核心',
            'default'     => '2',
            'key'         => 'cpu_limit',
        ],
        'max_cpu_per_container' => [
            'type'        => 'text',
            'name'        => '单容器CPU限制',
            'description' => '单个容器最大CPU核心数，0表示不限制',
            'default'     => '0',
            'key'         => 'max_cpu_per_container',
        ],
        'memory_limit' => [
            'type'        => 'text',
            'name'        => '内存总配额',
            'description' => '可用内存配额，单位：MB',
            'default'     => '1024',
            'key'         => 'memory_limit',
        ],
        'disk_limit' => [
            'type'        => 'text',
            'name'        => '硬盘总配额',
            'description' => '可用硬盘配额，单位：MB',
            'default'     => '10240',
            'key'         => 'disk_limit',
        ],
        'traffic_limit' => [
            'type'        => 'text',
            'name'        => '月流量限制',
            'description' => '可用流量配额，单位：GB',
            'default'     => '100',
            'key'         => 'traffic_limit',
        ],
        'ingress' => [
            'type'        => 'text',
            'name'        => '入站带宽',
            'description' => '下载带宽，单位：Mbit',
            'default'     => '100',
            'key'         => 'ingress',
        ],
        'egress' => [
            'type'        => 'text',
            'name'        => '出站带宽',
            'description' => '上传带宽，单位：Mbit',
            'default'     => '100',
            'key'         => 'egress',
        ],
        'ipv4_pool_limit' => [
            'type'        => 'text',
            'name'        => 'IPv4地址池限制',
            'description' => '可用IPv4地址配额，单位：个',
            'default'     => '0',
            'key'         => 'ipv4_pool_limit',
        ],
        'ipv4_mapping_limit' => [
            'type'        => 'text',
            'name'        => 'IPv4端口映射限制',
            'description' => '可用IPv4端口映射配额，单位：条',
            'default'     => '0',
            'key'         => 'ipv4_mapping_limit',
        ],
        'ipv6_pool_limit' => [
            'type'        => 'text',
            'name'        => 'IPv6地址池限制',
            'description' => '可用IPv6地址配额，单位：个',
            'default'     => '0',
            'key'         => 'ipv6_pool_limit',
        ],
        'ipv6_mapping_limit' => [
            'type'        => 'text',
            'name'        => 'IPv6端口映射限制',
            'description' => '可用IPv6端口映射配额，单位：条',
            'default'     => '0',
            'key'         => 'ipv6_mapping_limit',
        ],
        'reverse_proxy_limit' => [
            'type'        => 'text',
            'name'        => '反向代理限制',
            'description' => '可用反向代理配额，单位：条',
            'default'     => '0',
            'key'         => 'reverse_proxy_limit',
        ],
        'cpu_allowance' => [
            'type'        => 'text',
            'name'        => 'CPU使用率限制',
            'description' => 'CPU使用率，单位：%',
            'default'     => '50',
            'key'         => 'cpu_allowance',
        ],
        'io_read' => [
            'type'        => 'text',
            'name'        => '磁盘读取限制',
            'description' => '磁盘读取速度，单位：MB/s',
            'default'     => '100',
            'key'         => 'io_read',
        ],
        'io_write' => [
            'type'        => 'text',
            'name'        => '磁盘写入限制',
            'description' => '磁盘写入速度，单位：MB/s',
            'default'     => '50',
            'key'         => 'io_write',
        ],
        'processes_limit' => [
            'type'        => 'text',
            'name'        => '最大进程数',
            'description' => '进程数配额，单位：个',
            'default'     => '512',
            'key'         => 'processes_limit',
        ],
        'allow_nesting' => [
            'type'        => 'dropdown',
            'name'        => '嵌套虚拟化',
            'description' => '嵌套虚拟化，支持Docker',
            'default'     => 'true',
            'key'         => 'allow_nesting',
            'options'     => ['true' => '启用', 'false' => '禁用'],
        ],
        'memory_swap' => [
            'type'        => 'dropdown',
            'name'        => 'Swap开关',
            'description' => '虚拟内存',
            'default'     => 'true',
            'key'         => 'memory_swap',
            'options'     => ['true' => '启用', 'false' => '禁用'],
        ],
    ];
}

function lxdwebserver_ApiRequest($params, $endpoint, $data = [], $method = 'POST')
{
    $curl = curl_init();
    $url = 'https://' . $params['server_ip'] . ':' . $params['port'] . $endpoint;
    
    $curlOptions = [
        CURLOPT_URL            => $url,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 30,
        CURLOPT_CUSTOMREQUEST  => $method,
        CURLOPT_HTTPHEADER     => [
            'X-API-Hash: ' . $params['accesshash'],
            'Content-Type: application/json',
        ],
        CURLOPT_SSL_VERIFYPEER => false,
        CURLOPT_SSL_VERIFYHOST => false,
    ];
    
    if ($method === 'POST' || $method === 'PUT') {
        if (!empty($data)) {
            $curlOptions[CURLOPT_POSTFIELDS] = json_encode($data);
        }
    }
    
    curl_setopt_array($curl, $curlOptions);
    $response = curl_exec($curl);
    curl_close($curl);
    
    return json_decode($response, true);
}

function lxdwebserver_TestLink($params)
{
    $res = lxdwebserver_ApiRequest($params, '/api/system/users', [], 'GET');
    
    if (isset($res['code']) && $res['code'] == 200) {
        return [
            'status' => 200,
            'data'   => ['server_status' => 1, 'msg' => '连接成功']
        ];
    }
    
    return [
        'status' => 200,
        'data'   => ['server_status' => 0, 'msg' => '连接失败: ' . ($res['msg'] ?? '未知错误')]
    ];
}

function lxdwebserver_CreateAccount($params)
{
    $username = is_array($params['domain']) ? $params['domain'][0] : $params['domain'];
    $configoptions = $params['configoptions'];
    
    $requestData = [
        'username'            => $username,
        'password'            => $params['password'],
        'cpu_quota'           => (int)($configoptions['cpu_limit'] ?? 2),
        'max_cpu_per_container' => (int)($configoptions['max_cpu_per_container'] ?? 0),
        'memory_quota'        => (int)($configoptions['memory_limit'] ?? 1024),
        'disk_quota'          => (int)($configoptions['disk_limit'] ?? 10240),
        'traffic_limit'       => (int)($configoptions['traffic_limit'] ?? 100),
        'ingress'             => (int)($configoptions['ingress'] ?? 100),
        'egress'              => (int)($configoptions['egress'] ?? 100),
        'ipv4_pool_limit'     => (int)($configoptions['ipv4_pool_limit'] ?? 0),
        'ipv4_mapping_limit'  => (int)($configoptions['ipv4_mapping_limit'] ?? 0),
        'ipv6_pool_limit'     => (int)($configoptions['ipv6_pool_limit'] ?? 0),
        'ipv6_mapping_limit'  => (int)($configoptions['ipv6_mapping_limit'] ?? 0),
        'reverse_proxy_limit' => (int)($configoptions['reverse_proxy_limit'] ?? 0),
        'cpu_allowance'       => (int)($configoptions['cpu_allowance'] ?? 50),
        'io_read'             => (int)($configoptions['io_read'] ?? 100),
        'io_write'            => (int)($configoptions['io_write'] ?? 50),
        'processes_limit'     => (int)($configoptions['processes_limit'] ?? 512),
        'allow_nesting'       => ($configoptions['allow_nesting'] ?? 'true') === 'true',
        'memory_swap'         => ($configoptions['memory_swap'] ?? 'true') === 'true',
    ];
    
    $res = lxdwebserver_ApiRequest($params, '/api/system/users', $requestData, 'POST');
    
    if (isset($res['code']) && $res['code'] == 200) {
        try {
            Db::name('host')->where('id', $params['hostid'])->update([
                'domainstatus' => 'Active',
                'username'     => $username,
                'password'     => $res['data']['user']['password'] ?? $params['password'],
                'dedicatedip'  => $params['server_ip'],
                'bwlimit'      => (int)($configoptions['traffic_limit'] ?? 100),
            ]);
        } catch (\Exception $e) {
            return ['status' => 'error', 'msg' => '创建成功但同步数据失败'];
        }
        return ['status' => 'success', 'msg' => '用户创建成功'];
    }
    
    return ['status' => 'error', 'msg' => $res['msg'] ?? '创建失败'];
}

function lxdwebserver_TerminateAccount($params)
{
    $username = is_array($params['domain']) ? $params['domain'][0] : $params['domain'];
    
    $users = lxdwebserver_ApiRequest($params, '/api/system/users', [], 'GET');
    if (!isset($users['code']) || $users['code'] != 200) {
        return ['status' => 'error', 'msg' => '获取用户列表失败'];
    }
    
    $userId = null;
    foreach ($users['data']['users'] ?? [] as $user) {
        if ($user['username'] === $username) {
            $userId = $user['id'];
            break;
        }
    }
    
    if (!$userId) {
        return ['status' => 'success', 'msg' => '用户不存在，视为已删除'];
    }
    
    $res = lxdwebserver_ApiRequest($params, '/api/system/users/' . $userId, [], 'DELETE');
    
    if (isset($res['code']) && $res['code'] == 200) {
        return ['status' => 'success', 'msg' => '用户删除成功'];
    }
    
    return ['status' => 'error', 'msg' => $res['msg'] ?? '删除失败'];
}

function lxdwebserver_SuspendAccount($params)
{
    $username = is_array($params['domain']) ? $params['domain'][0] : $params['domain'];
    
    $users = lxdwebserver_ApiRequest($params, '/api/system/users', [], 'GET');
    $userId = null;
    foreach ($users['data']['users'] ?? [] as $user) {
        if ($user['username'] === $username) {
            $userId = $user['id'];
            break;
        }
    }
    
    if (!$userId) {
        return ['status' => 'error', 'msg' => '用户不存在'];
    }
    
    $res = lxdwebserver_ApiRequest($params, '/api/system/users/' . $userId, ['status' => 'disabled'], 'PUT');
    
    if (isset($res['code']) && $res['code'] == 200) {
        return ['status' => 'success', 'msg' => '用户已暂停'];
    }
    
    return ['status' => 'error', 'msg' => $res['msg'] ?? '暂停失败'];
}

function lxdwebserver_UnsuspendAccount($params)
{
    $username = is_array($params['domain']) ? $params['domain'][0] : $params['domain'];
    
    $users = lxdwebserver_ApiRequest($params, '/api/system/users', [], 'GET');
    $userId = null;
    foreach ($users['data']['users'] ?? [] as $user) {
        if ($user['username'] === $username) {
            $userId = $user['id'];
            break;
        }
    }
    
    if (!$userId) {
        return ['status' => 'error', 'msg' => '用户不存在'];
    }
    
    $res = lxdwebserver_ApiRequest($params, '/api/system/users/' . $userId, ['status' => 'active'], 'PUT');
    
    if (isset($res['code']) && $res['code'] == 200) {
        return ['status' => 'success', 'msg' => '用户已恢复'];
    }
    
    return ['status' => 'error', 'msg' => $res['msg'] ?? '恢复失败'];
}

function lxdwebserver_CrackPassword($params, $new_pass)
{
    $username = is_array($params['domain']) ? $params['domain'][0] : $params['domain'];
    $userId = lxdwebserver_GetUserId($params, $username);
    
    if (!$userId) {
        return ['status' => 'error', 'msg' => '用户不存在'];
    }
    
    $requestData = ['password' => $new_pass];
    $res = lxdwebserver_ApiRequest($params, '/api/system/users/' . $userId . '/regenerate-key', $requestData, 'POST');
    
    if (isset($res['code']) && $res['code'] == 200) {
        try {
            Db::name('host')->where('id', $params['hostid'])->update(['password' => $new_pass]);
        } catch (\Exception $e) {}
        return ['status' => 'success', 'msg' => '密码已重置'];
    }
    
    return ['status' => 'error', 'msg' => $res['msg'] ?? '密码重置失败'];
}

function lxdwebserver_GetUserId($params, $username)
{
    $users = lxdwebserver_ApiRequest($params, '/api/system/users', [], 'GET');
    foreach ($users['data']['users'] ?? [] as $user) {
        if ($user['username'] === $username) {
            return $user['id'];
        }
    }
    return null;
}

function lxdwebserver_Status($params)
{
    $username = is_array($params['domain']) ? $params['domain'][0] : $params['domain'];
    
    $users = lxdwebserver_ApiRequest($params, '/api/system/users', [], 'GET');
    foreach ($users['data']['users'] ?? [] as $user) {
        if ($user['username'] === $username) {
            $result = ['status' => 'success'];
            if ($user['status'] === 'active') {
                $result['data']['status'] = 'on';
                $result['data']['des'] = '正常';
            } else {
                $result['data']['status'] = 'suspend';
                $result['data']['des'] = '已禁用';
            }
            $originalTraffic = Db::name('products')
        ->where('id', $params['productid'])
        ->value('config_option7');
    $trafficLimit = $originalTraffic ? (int)$originalTraffic : 10;
    Db::name('host')->where('id', $params['hostid'])->update(['bwlimit' => $trafficLimit]);
    
    return $result;
        }
    }
    
    return ['status' => 'error', 'msg' => '用户不存在'];
}

function lxdwebserver_UsageUpdate($params)
{
    $username = is_array($params['domain']) ? $params['domain'][0] : $params['domain'];
    
    $containers = lxdwebserver_ApiRequest($params, '/api/system/containers?username=' . urlencode($username), [], 'GET');
    
    if (!$containers || !isset($containers['code']) || $containers['code'] != 200) {
        return ['status' => 'error', 'msg' => '获取容器列表失败'];
    }
    
    $totalUsedGB = 0;
    foreach ($containers['data'] ?? [] as $container) {
        $name = $container['name'] ?? '';
        if (!$name) continue;
        
        $trafficRes = lxdwebserver_ApiRequest($params, '/api/system/traffic?name=' . urlencode($name), [], 'GET');
        if ($trafficRes && isset($trafficRes['code']) && $trafficRes['code'] == 200 && isset($trafficRes['data']['TotalGB'])) {
            $totalUsedGB += (float)$trafficRes['data']['TotalGB'];
        }
    }
    
    Db::name('host')->where('id', $params['hostid'])->update(['bwusage' => $totalUsedGB]);
    
    return ['status' => 'success', 'msg' => '流量同步成功'];
}

function lxdwebserver_Sync($params)
{
    $username = is_array($params['domain']) ? $params['domain'][0] : $params['domain'];
    
    $users = lxdwebserver_ApiRequest($params, '/api/system/users', [], 'GET');
    foreach ($users['data']['users'] ?? [] as $user) {
        if ($user['username'] === $username) {
            try {
                $update = [];
                if ($user['status'] === 'active') {
                    $update['domainstatus'] = 'Active';
                } else {
                    $update['domainstatus'] = 'Suspended';
                }
                
                if (isset($user['traffic_limit'])) {
                    $update['bwlimit'] = (int)$user['traffic_limit'];
                }
                
                $containers = lxdwebserver_ApiRequest($params, '/api/system/containers?username=' . urlencode($username), [], 'GET');
                if ($containers && isset($containers['code']) && $containers['code'] == 200) {
                    $totalUsedGB = 0;
                    foreach ($containers['data'] ?? [] as $container) {
                        $name = $container['name'] ?? '';
                        if (!$name) continue;
                        $trafficRes = lxdwebserver_ApiRequest($params, '/api/system/traffic?name=' . urlencode($name), [], 'GET');
                        if ($trafficRes && isset($trafficRes['code']) && $trafficRes['code'] == 200 && isset($trafficRes['data']['TotalGB'])) {
                            $totalUsedGB += (float)$trafficRes['data']['TotalGB'];
                        }
                    }
                    $update['bwusage'] = $totalUsedGB;
                }
                
                if (!empty($update)) {
                    Db::name('host')->where('id', $params['hostid'])->update($update);
                }
                return ['status' => 'success', 'msg' => '同步成功'];
            } catch (\Exception $e) {
                return ['status' => 'error', 'msg' => '同步失败: ' . $e->getMessage()];
            }
        }
    }
    
    return ['status' => 'error', 'msg' => '用户不存在'];
}

function lxdwebserver_AdminButton($params)
{
    if (!empty($params['domain'])) {
        return [
            'Sync' => '同步状态',
            'TrafficReset' => '重置流量',
        ];
    }
    return [];
}

function lxdwebserver_TrafficReset($params)
{
    $username = is_array($params['domain']) ? $params['domain'][0] : $params['domain'];
    
    $res = lxdwebserver_ApiRequest($params, '/api/system/traffic/reset?username=' . urlencode($username), [], 'POST');
    
    $originalTraffic = Db::name('products')
        ->where('id', $params['productid'])
        ->value('config_option7');
    $trafficLimit = $originalTraffic ? (int)$originalTraffic : 10;
    Db::name('host')->where('id', $params['hostid'])->update(['bwlimit' => $trafficLimit]);
    
    if (isset($res['code']) && $res['code'] == 200) {
        return ['status' => 'success', 'msg' => $res['msg'] ?? '流量重置成功'];
    }
    
    return ['status' => 'error', 'msg' => $res['msg'] ?? '流量重置失败'];
}

function lxdwebserver_RegenerateKey($params)
{
    $username = is_array($params['domain']) ? $params['domain'][0] : $params['domain'];
    $userId = lxdwebserver_GetUserId($params, $username);
    
    if (!$userId) {
        return ['status' => 'error', 'msg' => '用户不存在'];
    }
    
    $res = lxdwebserver_ApiRequest($params, '/api/system/users/' . $userId . '/regenerate-key', [], 'POST');
    
    if (isset($res['code']) && $res['code'] == 200) {
        return ['status' => 'success', 'msg' => 'API Key已重置'];
    }
    
    return ['status' => 'error', 'msg' => $res['msg'] ?? '重置失败'];
}

function lxdwebserver_ClientArea($params)
{
    return [
        'info' => ['name' => '用户中心'],
    ];
}

function lxdwebserver_ClientAreaOutput($params, $key)
{
    if ($key == 'info') {
        $username = is_array($params['domain']) ? $params['domain'][0] : $params['domain'];
        
        $res = lxdwebserver_ApiRequest($params, '/api/system/users/' . urlencode($username) . '/access-token', [], 'GET');
        
        $jumpUrl = '';
        $errorMsg = '';
        
        if (isset($res['code']) && $res['code'] == 200 && isset($res['data'])) {
            $baseUrl = 'https://' . $params['server_ip'] . ':' . $params['port'];
            $jumpUrl = $baseUrl . $res['data']['jump_url'];
        } else {
            $errorMsg = $res['msg'] ?? '获取访问令牌失败';
        }
        
        return [
            'template' => 'templates/info.html',
            'vars' => [
                'username'    => $username,
                'server_ip'   => $params['server_ip'],
                'server_port' => $params['port'],
                'jump_url'    => $jumpUrl,
                'error_msg'   => $errorMsg,
            ]
        ];
    }
    
    return '';
}


function lxdwebserver_ChangePackage($params)
{
    $username = is_array($params['domain']) ? $params['domain'][0] : $params['domain'];
    $userId = lxdwebserver_GetUserId($params, $username);
    
    if (!$userId) {
        return ['status' => 'error', 'msg' => '用户不存在'];
    }
    
    $configoptions = $params['configoptions'];
    
    $requestData = [
        'cpu_quota'           => (int)($configoptions['cpu_limit'] ?? 0) ?: null,
        'max_cpu_per_container' => (int)($configoptions['max_cpu_per_container'] ?? 0) ?: null,
        'memory_quota'        => (int)($configoptions['memory_limit'] ?? 0) ?: null,
        'disk_quota'          => (int)($configoptions['disk_limit'] ?? 0) ?: null,
        'traffic_limit'       => (int)($configoptions['traffic_limit'] ?? 0) ?: null,
        'ingress'             => (int)($configoptions['ingress'] ?? 0) ?: null,
        'egress'              => (int)($configoptions['egress'] ?? 0) ?: null,
        'ipv4_pool_limit'     => (int)($configoptions['ipv4_pool_limit'] ?? 0) ?: null,
        'ipv4_mapping_limit'  => (int)($configoptions['ipv4_mapping_limit'] ?? 0) ?: null,
        'ipv6_pool_limit'     => (int)($configoptions['ipv6_pool_limit'] ?? 0) ?: null,
        'ipv6_mapping_limit'  => (int)($configoptions['ipv6_mapping_limit'] ?? 0) ?: null,
        'reverse_proxy_limit' => (int)($configoptions['reverse_proxy_limit'] ?? 0) ?: null,
        'cpu_allowance'       => (int)($configoptions['cpu_allowance'] ?? 0) ?: null,
        'io_read'             => (int)($configoptions['io_read'] ?? 0) ?: null,
        'io_write'            => (int)($configoptions['io_write'] ?? 0) ?: null,
        'processes_limit'     => (int)($configoptions['processes_limit'] ?? 0) ?: null,
    ];
    
    if (isset($configoptions['allow_nesting'])) {
        $requestData['allow_nesting'] = $configoptions['allow_nesting'] === 'true';
    }
    if (isset($configoptions['memory_swap'])) {
        $requestData['memory_swap'] = $configoptions['memory_swap'] === 'true';
    }
    
    $requestData = array_filter($requestData, function($v) { return $v !== null; });
    
    $res = lxdwebserver_ApiRequest($params, '/api/system/users/' . $userId, $requestData, 'PUT');
    
    if (isset($res['code']) && $res['code'] == 200) {
        if (isset($configoptions['traffic_limit'])) {
            Db::name('host')->where('id', $params['hostid'])->update([
                'bwlimit' => (int)$configoptions['traffic_limit']
            ]);
        }
        return ['status' => 'success', 'msg' => '配置升级成功'];
    }
    
    return ['status' => 'error', 'msg' => $res['msg'] ?? '升级失败'];
}

function lxdwebserver_FlowPacketPaid($params)
{
    $username = is_array($params['domain']) ? $params['domain'][0] : $params['domain'];
    $userId = lxdwebserver_GetUserId($params, $username);
    
    if (!$userId) {
        return ['status' => 'error', 'msg' => '用户不存在'];
    }
    
    $capacity = Db::name('dcim_buy_record')
        ->where('type', 'flow_packet')
        ->where('hostid', $params['hostid'])
        ->where('uid', $params['uid'])
        ->where('status', 1)
        ->where('show_status', 0)
        ->where('pay_time', '>', strtotime(date('Y-m-01 00:00:00')))
        ->sum('capacity');
    
    $originalTraffic = (int)Db::name('host')->where('id', $params['hostid'])->value('bwlimit');
    $originalTraffic = $originalTraffic ?: 100;
    
    $totalTraffic = $originalTraffic + (int)$capacity;
    
    $requestData = ['traffic_limit' => $totalTraffic];
    $res = lxdwebserver_ApiRequest($params, '/api/system/users/' . $userId, $requestData, 'PUT');
    
    Db::name('host')->where('id', $params['hostid'])->update(['bwlimit' => $totalTraffic]);
    
    if ($res && isset($res['code']) && $res['code'] == 200) {
        return ['status' => 'success', 'msg' => '流量包已生效'];
    }
    
    return ['status' => 'error', 'msg' => $res['msg'] ?? '更新失败'];
}

function lxdwebserver_DailyCron()
{
    if (date('Y-m-d') != date('Y-m-01')) {
        return;
    }
    
    $host_data = Db::name('host')
        ->alias('h')
        ->leftJoin('servers s', 'h.serverid=s.id')
        ->where('s.type', 'lxdwebserver')
        ->whereIn('h.domainstatus', ['Active', 'Suspended'])
        ->field('h.*')
        ->select()
        ->toArray();
    
    $model = new \app\common\model\HostModel();
    foreach ($host_data as $v) {
        try {
            $params = $model->getProvisionParams($v['id']);
            $username = is_array($params['domain']) ? $params['domain'][0] : $params['domain'];
            $userId = lxdwebserver_GetUserId($params, $username);
            
            $originalTraffic = 0;
            
            $hostConfig = Db::name('host_config_options')
                ->where('relid', $v['id'])
                ->find();
            
            if ($hostConfig) {
                $configOption = Db::name('product_config_options_sub')
                    ->where('config_id', $hostConfig['configid'])
                    ->where('id', $hostConfig['optionid'])
                    ->find();
                
                if ($configOption && strpos($configOption['option_name'], '|') !== false) {
                    $originalTraffic = (int)explode('|', $configOption['option_name'])[0];
                }
            }
            
            if (!$originalTraffic) {
                $originalTraffic = (int)($params['configoptions']['traffic_limit'] ?? 0);
                if (!$originalTraffic) {
                    $originalTraffic = Db::name('products')
                        ->where('id', $v['productid'])
                        ->value('config_option4');
                    $originalTraffic = $originalTraffic ? (int)$originalTraffic : 100;
                }
            }
            
            if ($userId) {
                $requestData = ['traffic_limit' => $originalTraffic];
                lxdwebserver_ApiRequest($params, '/api/system/users/' . $userId, $requestData, 'PUT');
            }
        } catch (Exception $e) {
        }
        
        Db::name('host')->where('id', $v['id'])->update(['bwlimit' => $originalTraffic]);
    }
}

function lxdwebserver_FiveMinuteCron()
{
    $now = date('Y-m-d H:i');
    $start = date('Y-m-01') . ' 00:00';
    $end = date('Y-m-01') . ' 00:05';
    if ($now >= $start && $now <= $end) {
        lxdwebserver_DailyCron();
    }
}
