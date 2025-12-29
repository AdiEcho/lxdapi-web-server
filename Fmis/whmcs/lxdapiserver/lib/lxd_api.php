<?php

class LXD_API
{
    private $serverip;
    private $serverport;
    private $apikey;
    private $protocol = 'https';
    private $timeout = 30;
    
    public function __construct($params)
    {
        $this->serverip = !empty($params['serverhostname']) ? $params['serverhostname'] : ($params['serverip'] ?? '');
        $this->serverport = $params['serverport'] ?: '8443';
        $this->apikey = $params['serveraccesshash'] ?? '';
    }
    
    public function get($endpoint, $data = [])
    {
        return $this->request('GET', $endpoint, $data);
    }
    
    public function post($endpoint, $data = [])
    {
        return $this->request('POST', $endpoint, $data);
    }
    
    public function delete($endpoint, $data = [])
    {
        return $this->request('DELETE', $endpoint, $data);
    }
    
    private function request($method, $endpoint, $data = [])
    {
        if (empty($this->serverip)) {
            throw new Exception("服务器地址未配置，请在WHMCS服务器设置中填写主机名或IP地址");
        }
        $url = $this->protocol . '://' . $this->serverip . ':' . $this->serverport . $endpoint;
        
        if ($method === 'GET' && !empty($data) && strpos($endpoint, '?') === false) {
            $url .= '?' . http_build_query($data);
        }
        
        $ch = curl_init();
        
        $headers = [
            'X-API-Hash: ' . $this->apikey,
            'Content-Type: application/json',
        ];
        
        curl_setopt_array($ch, [
            CURLOPT_URL => $url,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => $this->timeout,
            CURLOPT_CONNECTTIMEOUT => 10,
            CURLOPT_HTTP_VERSION => CURL_HTTP_VERSION_1_1,
            CURLOPT_CUSTOMREQUEST => $method,
            CURLOPT_HTTPHEADER => $headers,
            CURLOPT_SSL_VERIFYPEER => false,
            CURLOPT_SSL_VERIFYHOST => false,
            CURLOPT_SSLVERSION => CURL_SSLVERSION_TLSv1_2,
        ]);
        
        if (($method === 'POST' || $method === 'DELETE') && !empty($data)) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($data));
        }
        
        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $curlError = curl_error($ch);
        $curlErrno = curl_errno($ch);
        curl_close($ch);
        
        if ($curlErrno) {
            $errorMessages = [
                3 => 'URL格式错误',
                6 => '无法解析主机名',
                7 => '无法连接到服务器',
                28 => '连接超时',
                35 => 'SSL/TLS握手失败',
                60 => 'SSL证书验证失败',
            ];
            $errorDesc = $errorMessages[$curlErrno] ?? "错误码: {$curlErrno}";
            $errorDetail = $curlError ?: $errorDesc;
            throw new Exception("连接失败 [{$url}]: {$errorDetail}");
        }
        
        if (empty($response)) {
            throw new Exception("服务器返回空响应 (HTTP {$httpCode})");
        }
        
        $decoded = json_decode($response, true);
        if (json_last_error() !== JSON_ERROR_NONE) {
            throw new Exception("响应解析失败: " . json_last_error_msg());
        }
        
        if ($httpCode >= 200 && $httpCode < 300) {
            return [
                'success' => isset($decoded['code']) ? $decoded['code'] == 200 : true,
                'message' => $decoded['msg'] ?? $decoded['message'] ?? '',
                'data' => $decoded['data'] ?? $decoded,
            ];
        }
        
        return [
            'success' => false,
            'message' => $decoded['msg'] ?? $decoded['message'] ?? 'HTTP ' . $httpCode,
            'data' => null,
        ];
    }
}
