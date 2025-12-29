<?php
/**
 * LXD API 封装类 for SWAPIDC
 */

class LXD_API {
    private $serverip;
    private $serverport;
    private $apikey;
    private $protocol = 'https';
    private $timeout = 30;
    
    public function __construct($data) {
        $this->serverip = $data['serverip'] ?? '';
        $this->serverport = $data['serverport'] ?? '8443';
        $this->apikey = $data['serveraccesshash'] ?? '';
    }
    
    public function get($endpoint, $params = []) {
        return $this->request('GET', $endpoint, $params);
    }
    
    public function post($endpoint, $params = []) {
        return $this->request('POST', $endpoint, $params);
    }
    
    public function delete($endpoint, $params = []) {
        return $this->request('DELETE', $endpoint, $params);
    }
    
    private function request($method, $endpoint, $params = []) {
        if (empty($this->serverip)) {
            throw new Exception("服务器地址未配置");
        }
        
        $url = $this->protocol . '://' . $this->serverip . ':' . $this->serverport . $endpoint;
        
        if ($method === 'GET' && !empty($params) && strpos($endpoint, '?') === false) {
            $url .= '?' . http_build_query($params);
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
        
        if (($method === 'POST' || $method === 'DELETE') && !empty($params)) {
            curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($params));
        }
        
        $response = curl_exec($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $curlError = curl_error($ch);
        $curlErrno = curl_errno($ch);
        curl_close($ch);
        
        if ($curlErrno) {
            throw new Exception("连接失败: {$curlError}");
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
