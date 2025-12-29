<?php
/**
 * SWAPIDC-LXD对接插件 by xkatld
 * 
 * @author xkatld
 * @version 2.0.2
 * @link https://github.com/xkatld/lxdapi-web-server
 */

require_once __DIR__ . '/includes/lxd_api.php';

function swapidc_lxdapi_ConfigOptions() {
    return array(
        "CPU核心数" => array("Type" => "text", "Size" => "10"),
        "内存 (MB)" => array("Type" => "text", "Size" => "10"),
        "硬盘 (MB)" => array("Type" => "text", "Size" => "10"),
        "系统镜像" => array("Type" => "text", "Size" => "25"),
        "入站带宽 (Mbit)" => array("Type" => "text", "Size" => "10"),
        "出站带宽 (Mbit)" => array("Type" => "text", "Size" => "10"),
        "月流量限制 (GB)" => array("Type" => "text", "Size" => "10"),
        "IPv4地址池限制" => array("Type" => "text", "Size" => "10"),
        "IPv4端口映射限制" => array("Type" => "text", "Size" => "10"),
        "IPv6地址池限制" => array("Type" => "text", "Size" => "10"),
        "IPv6端口映射限制" => array("Type" => "text", "Size" => "10"),
        "反向代理限制" => array("Type" => "text", "Size" => "10"),
        "CPU使用率限制 (%)" => array("Type" => "text", "Size" => "10"),
        "磁盘读取限制 (MB/s)" => array("Type" => "text", "Size" => "10"),
        "磁盘写入限制 (MB/s)" => array("Type" => "text", "Size" => "10"),
        "最大进程数" => array("Type" => "text", "Size" => "10"),
        "嵌套虚拟化" => array("Type" => "text", "Size" => "10"),
        "Swap开关" => array("Type" => "text", "Size" => "10"),
        "特权模式" => array("Type" => "text", "Size" => "10")
    );
}

function lxdapi_log($message) {
    $logFile = __DIR__ . '/lxdapi_debug.log';
    $time = date('Y-m-d H:i:s');
    file_put_contents($logFile, "[$time] $message\n", FILE_APPEND);
}

function lxdapi_generate_password($length = 16) {
    $chars = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!@#$%^&*';
    $password = '';
    for ($i = 0; $i < $length; $i++) {
        $password .= $chars[rand(0, strlen($chars) - 1)];
    }
    return $password;
}

function get_container_name($data) {
    if (!empty($data['注释'])) {
        return $data['注释'];
    }
    $serviceid = $data['serviceid'] ?? 0;
    if ($serviceid) {
        $result = full_query("SELECT 注释 FROM 服务 WHERE id = " . intval($serviceid));
        if ($row = mysqli_fetch_assoc($result)) {
            if (!empty($row['注释'])) {
                return $row['注释'];
            }
        }
    }
    return 'lxd' . rand(1000, 9999) . $data['serviceid'];
}

function swapidc_lxdapi_CreateAccount($data) {
    lxdapi_log("开始创建账户，服务ID: {$data['serviceid']}");
    
    try {
        $api = new LXD_API($data);
        $password = lxdapi_generate_password();
        $containerName = 'lxd' . rand(1000, 9999) . $data['serviceid'];
        
        $requestData = [
            'name' => $containerName,
            'image' => $data['configoption4'] ?? 'alpine320',
            'username' => 'user' . $data['uid'],
            'password' => $password,
            'cpu' => (int)($data['configoption1'] ?? 1),
            'memory' => (int)($data['configoption2'] ?? 512),
            'disk' => (int)($data['configoption3'] ?? 1024),
            'ingress' => (int)($data['configoption5'] ?? 100),
            'egress' => (int)($data['configoption6'] ?? 100),
            'traffic_limit' => (int)($data['configoption7'] ?? 100),
            'ipv4_pool_limit' => (int)($data['configoption8'] ?? 0),
            'ipv4_mapping_limit' => (int)($data['configoption9'] ?? 0),
            'ipv6_pool_limit' => (int)($data['configoption10'] ?? 0),
            'ipv6_mapping_limit' => (int)($data['configoption11'] ?? 0),
            'reverse_proxy_limit' => (int)($data['configoption12'] ?? 0),
            'cpu_allowance' => (int)($data['configoption13'] ?? 50),
            'io_read' => (int)($data['configoption14'] ?? 100),
            'io_write' => (int)($data['configoption15'] ?? 50),
            'processes_limit' => (int)($data['configoption16'] ?? 512),
            'allow_nesting' => ($data['configoption17'] ?? 'true') === 'true',
            'memory_swap' => ($data['configoption18'] ?? 'true') === 'true',
            'privileged' => ($data['configoption19'] ?? 'false') === 'true',
        ];
        
        $result = $api->post('/api/system/containers', $requestData);
        
        if (!$result['success']) {
            lxdapi_log("创建容器失败: " . ($result['message'] ?? '未知错误'));
            return $result['message'] ?? '创建容器失败';
        }
        
        $ip = $result['data']['ipv4'] ?? 'DHCP';
        
        update_query("服务", [
            "用户名" => "root",
            "密码" => encrypt($password),
            "专用IP" => $ip,
            "注释" => $containerName
        ], ["id" => $data['serviceid']]);
        
        lxdapi_log("容器创建成功: $containerName");
        return "成功";
        
    } catch (Exception $e) {
        lxdapi_log("创建账户异常: " . $e->getMessage());
        return "创建失败: " . $e->getMessage();
    }
}

function swapidc_lxdapi_SuspendAccount($data) {
    lxdapi_log("暂停账户，服务ID: {$data['serviceid']}");
    
    try {
        $api = new LXD_API($data);
        $containerName = get_container_name($data);
        $result = $api->post('/api/system/containers/' . urlencode($containerName) . '/action?action=stop', []);
        return $result['success'] ? "成功" : ($result['message'] ?? '暂停失败');
    } catch (Exception $e) {
        return "暂停失败: " . $e->getMessage();
    }
}

function swapidc_lxdapi_UnsuspendAccount($data) {
    lxdapi_log("解除暂停，服务ID: {$data['serviceid']}");
    
    try {
        $api = new LXD_API($data);
        $containerName = get_container_name($data);
        $result = $api->post('/api/system/containers/' . urlencode($containerName) . '/action?action=start', []);
        return $result['success'] ? "成功" : ($result['message'] ?? '解除暂停失败');
    } catch (Exception $e) {
        return "解除暂停失败: " . $e->getMessage();
    }
}

function swapidc_lxdapi_TerminateAccount($data) {
    lxdapi_log("删除账户，服务ID: {$data['serviceid']}");
    
    try {
        $api = new LXD_API($data);
        $containerName = get_container_name($data);
        $result = $api->delete('/api/system/containers/' . urlencode($containerName));
        return $result['success'] ? "成功" : ($result['message'] ?? '删除失败');
    } catch (Exception $e) {
        return "删除失败: " . $e->getMessage();
    }
}

function swapidc_lxdapi_ChangePassword($data) {
    lxdapi_log("修改密码，服务ID: {$data['serviceid']}");
    
    try {
        $api = new LXD_API($data);
        $containerName = get_container_name($data);
        $newPassword = $data['password'] ?? lxdapi_generate_password();
        
        $result = $api->post('/api/system/containers/' . urlencode($containerName) . '/action?action=reset-password', [
            'password' => $newPassword
        ]);
        
        if ($result['success']) {
            update_query("服务", ["密码" => encrypt($newPassword)], ["id" => $data['serviceid']]);
            return "成功";
        }
        
        return $result['message'] ?? '修改密码失败';
    } catch (Exception $e) {
        return "修改密码失败: " . $e->getMessage();
    }
}

function swapidc_lxdapi_ClientArea($data) {
    $js_code = "
    <script>
    document.addEventListener('DOMContentLoaded', function() {
        var iframe = document.querySelector('iframe[src*=\"container/dashboard\"]');
        if (!iframe) return;
        var btnGroup = iframe.closest('.btn-group');
        if (btnGroup) {
            btnGroup.parentNode.insertBefore(iframe, btnGroup.nextSibling);
            btnGroup.style.display = 'none';
        }
        iframe.style.cssText = 'width:100%;height:80vh;border:1px solid #ddd;border-radius:8px;margin-top:15px;display:block;';
        
        var resetForm = document.querySelector('form#formrepass, form[action*=\"repass\"]');
        if (resetForm) resetForm.style.display = 'none';
        var resetLink = document.querySelector('a[href=\"#resetPass\"]');
        if (resetLink) resetLink.style.display = 'none';
        document.querySelectorAll('button, a').forEach(function(el) {
            if (el.textContent.includes('重置产品密码')) el.style.display = 'none';
        });
    });
    </script>
    ";
    
    try {
        $api = new LXD_API($data);
        $containerName = get_container_name($data);
        $result = $api->get('/api/system/containers/' . urlencode($containerName) . '/credential');
        
        if ($result['success'] && !empty($result['data']['access_code'])) {
            $accessCode = $result['data']['access_code'];
            $serverHost = $data['serverip'] ?? '';
            $serverPort = $data['serverport'] ?? '8443';
            $iframeUrl = 'https://' . $serverHost . ':' . $serverPort . '/container/dashboard/lite?hash=' . $accessCode;
            $panel_html = "<iframe src='{$iframeUrl}' style='width:100%;height:80vh;border:none;' frameborder='0' allowfullscreen></iframe>";
            return array("", "</li></ul>{$js_code}{$panel_html}<ul>");
        } else {
            $error_html = "<div style='background:#f8d7da;border:1px solid #f5c6cb;border-radius:6px;padding:15px;margin:10px 0;color:#721c24;'><strong>无法加载管理面板</strong><br>" . ($result['message'] ?? '获取访问码失败') . "</div>";
            return array("", "</li></ul>{$js_code}{$error_html}<ul>");
        }
    } catch (Exception $e) {
        $error_html = "<div style='background:#f8d7da;border:1px solid #f5c6cb;border-radius:6px;padding:15px;margin:10px 0;color:#721c24;'><strong>连接失败</strong><br>" . $e->getMessage() . "</div>";
        return array("", "</li></ul>{$js_code}{$error_html}<ul>");
    }
}
