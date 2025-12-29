<?php
/**
 * WHMCS-LXD对接插件 by xkatld
 *
 * @package    WHMCS-LXD对接插件 by xkatld
 * @author     xkatld
 * @version    v2.0.3
 * @link       https://github.com/xkatld/lxdapi-web-server
 */

if (!defined("WHMCS")) {
    die("This file cannot be accessed directly");
}

use WHMCS\Database\Capsule;

require_once __DIR__ . '/lib/lxd_api.php';
require_once __DIR__ . '/functions.php';

function lxdapiserver_MetaData()
{
    return [
        'DisplayName' => 'WHMCS-LXD对接插件 by xkatld',
        'APIVersion' => 'v2.0.3',
        'RequiresServer' => true,
        'DefaultNonSSLPort' => '8443',
        'DefaultSSLPort' => '8443',
        'ServiceSingleSignOnLabel' => 'Login to Console',
        'AdminSingleSignOnLabel' => 'Login to Console as Admin',
    ];
}

function lxdapiserver_TestConnection(array $params)
{
    try {
        $api = new LXD_API($params);
        $result = $api->get('/api/system/containers', []);
        
        if ($result['success']) {
            return [
                'success' => true,
                'error' => '',
            ];
        }
        
        return [
            'success' => false,
            'error' => $result['message'] ?: '连接失败',
        ];
        
    } catch (Exception $e) {
        return [
            'success' => false,
            'error' => $e->getMessage(),
        ];
    }
}

function lxdapiserver_ConfigOptions()
{
    return [
        'cpus' => [
            'FriendlyName' => 'CPU核心数',
            'Type' => 'text',
            'Size' => '10',
            'Default' => '1',
            'Description' => 'CPU核心数量',
        ],
        'memory' => [
            'FriendlyName' => '内存 (MB)',
            'Type' => 'text',
            'Size' => '10',
            'Default' => '512',
            'Description' => '内存大小，单位：MB',
        ],
        'disk' => [
            'FriendlyName' => '硬盘 (MB)',
            'Type' => 'text',
            'Size' => '10',
            'Default' => '1024',
            'Description' => '硬盘大小，单位：MB',
        ],
        'image' => [
            'FriendlyName' => '系统镜像',
            'Type' => 'text',
            'Size' => '25',
            'Default' => 'alpine320',
            'Description' => '系统镜像名称',
        ],
        'ingress' => [
            'FriendlyName' => '入站带宽 (Mbit)',
            'Type' => 'text',
            'Size' => '10',
            'Default' => '100',
            'Description' => '下载速度限制，单位：Mbit',
        ],
        'egress' => [
            'FriendlyName' => '出站带宽 (Mbit)',
            'Type' => 'text',
            'Size' => '10',
            'Default' => '100',
            'Description' => '上传速度限制，单位：Mbit',
        ],
        'traffic_limit' => [
            'FriendlyName' => '月流量限制 (GB)',
            'Type' => 'text',
            'Size' => '10',
            'Default' => '100',
            'Description' => '单位：GB',
        ],
        'ipv4_pool_limit' => [
            'FriendlyName' => 'IPv4地址池限制',
            'Type' => 'text',
            'Size' => '10',
            'Default' => '0',
            'Description' => 'IPv4独立地址数量上限',
        ],
        'ipv4_mapping_limit' => [
            'FriendlyName' => 'IPv4端口映射限制',
            'Type' => 'text',
            'Size' => '10',
            'Default' => '0',
            'Description' => 'IPv4端口转发规则上限',
        ],
        'ipv6_pool_limit' => [
            'FriendlyName' => 'IPv6地址池限制',
            'Type' => 'text',
            'Size' => '10',
            'Default' => '0',
            'Description' => 'IPv6独立地址数量上限',
        ],
        'ipv6_mapping_limit' => [
            'FriendlyName' => 'IPv6端口映射限制',
            'Type' => 'text',
            'Size' => '10',
            'Default' => '0',
            'Description' => 'IPv6端口转发规则上限',
        ],
        'reverse_proxy_limit' => [
            'FriendlyName' => '反向代理限制',
            'Type' => 'text',
            'Size' => '10',
            'Default' => '0',
            'Description' => '反向代理域名数量上限',
        ],
        'cpu_allowance' => [
            'FriendlyName' => 'CPU使用率限制 (%)',
            'Type' => 'text',
            'Size' => '10',
            'Default' => '50',
            'Description' => 'CPU占用百分比，单位：%',
        ],
        'io_read' => [
            'FriendlyName' => '磁盘读取限制 (MB/s)',
            'Type' => 'text',
            'Size' => '10',
            'Default' => '100',
            'Description' => '单位：MB/s',
        ],
        'io_write' => [
            'FriendlyName' => '磁盘写入限制 (MB/s)',
            'Type' => 'text',
            'Size' => '10',
            'Default' => '50',
            'Description' => '单位：MB/s',
        ],
        'processes_limit' => [
            'FriendlyName' => '最大进程数',
            'Type' => 'text',
            'Size' => '10',
            'Default' => '512',
            'Description' => '进程数量上限',
        ],
        'allow_nesting' => [
            'FriendlyName' => '嵌套虚拟化',
            'Type' => 'dropdown',
            'Options' => 'true,false',
            'Default' => 'true',
            'Description' => '支持Docker等虚拟化',
        ],
        'memory_swap' => [
            'FriendlyName' => 'Swap开关',
            'Type' => 'dropdown',
            'Options' => 'true,false',
            'Default' => 'true',
            'Description' => '虚拟内存开关',
        ],
        'privileged' => [
            'FriendlyName' => '特权模式',
            'Type' => 'dropdown',
            'Options' => 'true,false',
            'Default' => 'false',
            'Description' => '特权容器开关',
        ],
    ];
}

function lxdapiserver_CreateAccount(array $params)
{
    try {
        $api = new LXD_API($params);
        
        $password = lxdapiserver_generate_password();
        
        $containerName = 'lxd11451' . $params['clientsdetails']['userid'] . $params['serviceid'];
        
        $cpu = !empty($params['configoptions']['cpus']) ? $params['configoptions']['cpus'] : $params['configoption1'];
        $memory = !empty($params['configoptions']['memory']) ? $params['configoptions']['memory'] : $params['configoption2'];
        $disk = !empty($params['configoptions']['disk']) ? $params['configoptions']['disk'] : $params['configoption3'];
        $image = !empty($params['configoptions']['image']) ? $params['configoptions']['image'] : $params['configoption4'];
        $ingress = !empty($params['configoptions']['ingress']) ? $params['configoptions']['ingress'] : $params['configoption5'];
        $egress = !empty($params['configoptions']['egress']) ? $params['configoptions']['egress'] : $params['configoption6'];
        $traffic_limit = !empty($params['configoptions']['traffic_limit']) ? $params['configoptions']['traffic_limit'] : $params['configoption7'];
        $ipv4_pool_limit = !empty($params['configoptions']['ipv4_pool_limit']) ? $params['configoptions']['ipv4_pool_limit'] : $params['configoption8'];
        $ipv4_mapping_limit = !empty($params['configoptions']['ipv4_mapping_limit']) ? $params['configoptions']['ipv4_mapping_limit'] : $params['configoption9'];
        $ipv6_pool_limit = !empty($params['configoptions']['ipv6_pool_limit']) ? $params['configoptions']['ipv6_pool_limit'] : $params['configoption10'];
        $ipv6_mapping_limit = !empty($params['configoptions']['ipv6_mapping_limit']) ? $params['configoptions']['ipv6_mapping_limit'] : $params['configoption11'];
        $reverse_proxy_limit = !empty($params['configoptions']['reverse_proxy_limit']) ? $params['configoptions']['reverse_proxy_limit'] : $params['configoption12'];
        $cpu_allowance = !empty($params['configoptions']['cpu_allowance']) ? $params['configoptions']['cpu_allowance'] : $params['configoption13'];
        $io_read = !empty($params['configoptions']['io_read']) ? $params['configoptions']['io_read'] : $params['configoption14'];
        $io_write = !empty($params['configoptions']['io_write']) ? $params['configoptions']['io_write'] : $params['configoption15'];
        $processes_limit = !empty($params['configoptions']['processes_limit']) ? $params['configoptions']['processes_limit'] : $params['configoption16'];
        $allow_nesting = !empty($params['configoptions']['allow_nesting']) ? $params['configoptions']['allow_nesting'] === 'true' : $params['configoption17'] === 'true';
        $memory_swap = !empty($params['configoptions']['memory_swap']) ? $params['configoptions']['memory_swap'] === 'true' : $params['configoption18'] === 'true';
        $privileged = !empty($params['configoptions']['privileged']) ? $params['configoptions']['privileged'] === 'true' : $params['configoption19'] === 'true';
        
        $requestData = [
            'name' => $containerName,
            'image' => $image,
            'username' => 'user_' . $params['clientsdetails']['userid'],
            'password' => $password,
            'cpu' => (int)$cpu,
            'memory' => (int)$memory,
            'disk' => (int)$disk,
            'ingress' => (int)$ingress,
            'egress' => (int)$egress,
            'traffic_limit' => (int)$traffic_limit,
            'ipv4_pool_limit' => (int)$ipv4_pool_limit,
            'ipv4_mapping_limit' => (int)$ipv4_mapping_limit,
            'ipv6_pool_limit' => (int)$ipv6_pool_limit,
            'ipv6_mapping_limit' => (int)$ipv6_mapping_limit,
            'reverse_proxy_limit' => (int)$reverse_proxy_limit,
            'cpu_allowance' => (int)$cpu_allowance,
            'io_read' => (int)$io_read,
            'io_write' => (int)$io_write,
            'processes_limit' => (int)$processes_limit,
            'allow_nesting' => $allow_nesting,
            'memory_swap' => $memory_swap,
            'privileged' => $privileged,
        ];
        
        $result = $api->post('/api/system/containers', $requestData);
        
        if (!$result['success']) {
            return $result['message'] ?? '创建容器失败';
        }
        
        lxdapiserver_save_password($params['serviceid'], $password);
        
        $updateData = [
            'domain' => $containerName,
        ];
        
        if (!empty($result['data']['ipv4'])) {
            $updateData['dedicatedip'] = $result['data']['ipv4'];
        }
        
        Capsule::table('tblhosting')
            ->where('id', $params['serviceid'])
            ->update($updateData);
        
        return 'success';
        
    } catch (Exception $e) {
        lxdapiserver_log_error('CreateAccount', $e->getMessage());
        return $e->getMessage();
    }
}

function lxdapiserver_SuspendAccount(array $params)
{
    try {
        $api = new LXD_API($params);
        $result = $api->post('/api/system/containers/' . urlencode($params['domain']) . '/action?action=pause', []);
        
        return $result['success'] ? 'success' : ($result['message'] ?? '暂停失败');
        
    } catch (Exception $e) {
        return $e->getMessage();
    }
}

function lxdapiserver_UnsuspendAccount(array $params)
{
    try {
        $api = new LXD_API($params);
        $result = $api->post('/api/system/containers/' . urlencode($params['domain']) . '/action?action=resume', []);
        
        return $result['success'] ? 'success' : ($result['message'] ?? '恢复失败');
        
    } catch (Exception $e) {
        return $e->getMessage();
    }
}

function lxdapiserver_TerminateAccount(array $params)
{
    try {
        $api = new LXD_API($params);
        $result = $api->delete('/api/system/containers/' . urlencode($params['domain']));
        
        return $result['success'] ? 'success' : ($result['message'] ?? '删除失败');
        
    } catch (Exception $e) {
        return $e->getMessage();
    }
}

function lxdapiserver_ChangePassword(array $params)
{
    try {
        $api = new LXD_API($params);
        
        $result = $api->post('/api/system/containers/' . urlencode($params['domain']) . '/action?action=reset-password', [
            'password' => $params['password']
        ]);

        if ($result['success']) {
            lxdapiserver_save_password($params['serviceid'], $params['password']);
            return 'success';
        }
        
        return $result['message'] ?? '修改密码失败';
        
    } catch (Exception $e) {
        return $e->getMessage();
    }
}

function lxdapiserver_ClientArea(array $params)
{
    try {
        $api = new LXD_API($params);
        
        $result = $api->get('/api/system/containers/' . urlencode($params['domain']) . '/credential');
        
        $jumpUrl = '';
        $iframeUrl = '';
        $errorMsg = '';
        
        if ($result['success'] && !empty($result['data']['access_code'])) {
            $accessCode = $result['data']['access_code'];
            $protocol = 'https';
            $serverHost = !empty($params['serverhostname']) ? $params['serverhostname'] : $params['serverip'];
            $baseUrl = $protocol . '://' . $serverHost . ':' . $params['serverport'];
            $jumpUrl = $baseUrl . '/container/dashboard?hash=' . $accessCode;
            $iframeUrl = $baseUrl . '/container/dashboard/lite?hash=' . $accessCode;
        } else {
            $errorMsg = $result['message'] ?? '获取访问码失败';
        }
        
        return [
            'templatefile' => 'templates/overview',
            'vars' => [
                'jump_url' => $jumpUrl,
                'iframe_url' => $iframeUrl,
                'error_msg' => $errorMsg,
            ],
        ];
        
    } catch (Exception $e) {
        return [
            'templatefile' => 'templates/overview',
            'vars' => [
                'error_msg' => $e->getMessage(),
            ],
        ];
    }
}

function lxdapiserver_AdminCustomButtonArray()
{
    return [
        '开机' => 'start',
        '关机' => 'stop',
        '重启' => 'reboot',
        '重装系统' => 'reinstall',
        '同步状态' => 'sync',
        '重置流量' => 'traffic_reset',
    ];
}

function lxdapiserver_start(array $params)
{
    try {
        $api = new LXD_API($params);
        $result = $api->post('/api/system/containers/' . urlencode($params['domain']) . '/action?action=start', []);
        return $result['success'] ? 'success' : ($result['message'] ?? '开机失败');
    } catch (Exception $e) {
        return $e->getMessage();
    }
}

function lxdapiserver_stop(array $params)
{
    try {
        $api = new LXD_API($params);
        $result = $api->post('/api/system/containers/' . urlencode($params['domain']) . '/action?action=stop', []);
        return $result['success'] ? 'success' : ($result['message'] ?? '关机失败');
    } catch (Exception $e) {
        return $e->getMessage();
    }
}

function lxdapiserver_reboot(array $params)
{
    try {
        $api = new LXD_API($params);
        $result = $api->post('/api/system/containers/' . urlencode($params['domain']) . '/action?action=restart', []);
        return $result['success'] ? 'success' : ($result['message'] ?? '重启失败');
    } catch (Exception $e) {
        return $e->getMessage();
    }
}

function lxdapiserver_reinstall(array $params)
{
    try {
        $api = new LXD_API($params);
        $password = lxdapiserver_generate_password();
        
        $result = $api->post('/api/system/containers/' . urlencode($params['domain']) . '/action?action=reinstall', [
            'image' => $params['configoption4'],
            'password' => $password
        ]);
        
        if ($result['success']) {
            lxdapiserver_save_password($params['serviceid'], $password);
            return 'success';
        }
        
        return $result['message'] ?? '重装失败';
        
    } catch (Exception $e) {
        return $e->getMessage();
    }
}

function lxdapiserver_sync(array $params)
{
    try {
        $api = new LXD_API($params);
        $result = $api->get('/api/system/containers/' . urlencode($params['domain']));
        
        if ($result['success'] && !empty($result['data'])) {
            $updateData = [];
            
            if (!empty($result['data']['ipv4'])) {
                $updateData['dedicatedip'] = $result['data']['ipv4'];
            }
            
            if (isset($result['data']['status'])) {
                $status = strtoupper($result['data']['status']);
                if ($status === 'RUNNING') {
                    $updateData['domainstatus'] = 'Active';
                } elseif ($status === 'STOPPED') {
                    $updateData['domainstatus'] = 'Suspended';
                }
            }
            
            if (!empty($updateData)) {
                Capsule::table('tblhosting')
                    ->where('id', $params['serviceid'])
                    ->update($updateData);
            }
            
            return 'success';
        }
        
        return $result['message'] ?? '同步失败';
        
    } catch (Exception $e) {
        return $e->getMessage();
    }
}

function lxdapiserver_traffic_reset(array $params)
{
    try {
        $api = new LXD_API($params);
        $result = $api->post('/api/system/traffic/reset?name=' . urlencode($params['domain']), []);
        return $result['success'] ? 'success' : ($result['message'] ?? '重置流量失败');
    } catch (Exception $e) {
        return $e->getMessage();
    }
}

function lxdapiserver_AdminServicesTabFields(array $params)
{
    try {
        $api = new LXD_API($params);
        $result = $api->get('/api/system/containers/' . urlencode($params['domain']));
        
        if ($result['success'] && !empty($result['data'])) {
            $data = $result['data'];
            return [
                '容器状态' => $data['status'] ?? 'Unknown',
                'IPv4地址' => $data['ipv4'] ?? 'N/A',
                'IPv6地址' => $data['ipv6'] ?? 'N/A',
                'CPU使用率' => isset($data['cpu_percent']) ? number_format($data['cpu_percent'], 2) . '%' : 'N/A',
                '内存使用' => $data['memory_usage'] ?? 'N/A',
                '硬盘使用' => $data['disk_usage'] ?? 'N/A',
                '流量使用' => $data['traffic_usage'] ?? 'N/A',
            ];
        }
    } catch (Exception $e) {
        lxdapiserver_log_error('AdminServicesTabFields', $e->getMessage());
    }
    
    return [];
}

function lxdapiserver_ServiceSingleSignOn(array $params)
{
    try {
        $api = new LXD_API($params);

        $result = $api->post('/api/system/console/create-token', [
            'hostname' => $params['domain'],
        ]);

        if ($result['success'] && !empty($result['data']['token'])) {
            $serverHost = !empty($params['serverhostname']) ? $params['serverhostname'] : $params['serverip'];
            $consoleUrl = 'https://' . $serverHost . ':' . $params['serverport'] . '/console?token=' . $result['data']['token'];
            
            return [
                'success' => true,
                'redirectTo' => $consoleUrl,
            ];
        }

        return [
            'success' => false,
            'errorMsg' => $result['message'] ?? '创建控制台会话失败',
        ];
        
    } catch (Exception $e) {
        return [
            'success' => false,
            'errorMsg' => $e->getMessage(),
        ];
    }
}
