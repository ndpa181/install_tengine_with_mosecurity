#!/bin/bash

TENGINE_VERSION=2.3.0
DEPLOY_PATH=/usr/local/src/nginx_waf

if [ ! -d ${DEPLOY_PATH} ] ; then mkdir -p  ${DEPLOY_PATH}; fi

function install_gperftools(){
    echo -e "\033[1;31m **** 开始编译安装 google-gperftools **** \033[0m"
    ## 安装 gperftools
    cd ${DEPLOY_PATH} && \
    git clone https://github.com/gperftools/gperftools \
    && cd gperftools && sh autogen.sh && ./configure && make && make install
}

function install_luaJit(){
    cd ${DEPLOY_PATH} && \
    git clone https://github.com/openresty/luajit2 && \
    cd luajit2 && \
    make && make install
}

# nginx
function install_pre_utils(){
    echo -e "\033[1;31m **** 开始安装必须的前置包 **** \033[0m"
    yum -y install wget curl git ;
    yum install autoconf automake bzip2 \
         flex httpd-devel libaio-devel \
         libass-devel libjpeg-turbo-devel libpng12-devel \
         libtheora-devel libtool libva-devel libvdpau-devel \
         libvorbis-devel libxml2-devel libxslt-devel \
         perl texi2html unzip zip openssl \
         openssl-devel geoip geoip-devel gcc-c++ \
         gd-devel GeoIP GeoIP-devel GeoIP-data libxml2 libxml2-dev zlib-devel \
         perl perl-devel perl-ExtUtils-Embed redhat-rpm-config -y
}

## 编译ModSecurity
function install_modsecurity(){
    echo -e "\033[1;31m **** 开始安装Modsecurity **** \033[0m"

    if [ ! -d $DEPLOY_PATH"/ModSecurity-nginx" ]; then
        cd $DEPLOY_PATH && git clone https://github.com/SpiderLabs/ModSecurity-nginx.git ;
    fi

    if [ ! -d $DEPLOY_PATH"/ModSecurity" ]; then
        cd $DEPLOY_PATH && git clone https://github.com/SpiderLabs/ModSecurity \
        &&  cd ModSecurity  \
        &&  sh build.sh  \
        && yum install -y https://archives.fedoraproject.org/pub/archive/fedora/linux/updates/23/x86_64/b/bison-3.0.4-3.fc23.x86_64.rpm \
        &&  git submodule init  \
        &&  git submodule update  \
        &&  ./configure \
        && make && make install
    fi
    echo -e "\033[46;30m *****完成安装和下载 Nginx-Modsecurity****** \033[0m"
}

function get_common_modsecurity_conf(){
    ## 获取初始化`modsecurity.conf`文件
    wget https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/modsecurity.conf-recommended && \
        mv modsecurity.conf-recommended  /etc/nginx/modsecurity.conf
}

function download_tengine(){
    echo -e "\033[1;33m ** 准备下载 tengine-${TENGINE_VERSION} ** \033[0m"
    if [ ! -d ${DEPLOY_PATH}/tengine-${TENGINE_VERSION} ]; then
        cd $DEPLOY_PATH && wget https://github.com/alibaba/tengine/archive/${TENGINE_VERSION}.zip \
                && unzip ${TENGINE_VERSION}.zip -d ${DEPLOY_PATH}
     else
        echo -e "\033[1;33m ** tengine-${TENGINE_VERSION} 已存在 ** \033[0m"
     fi
}

function make_modsecurity_with_tengine(){
    download_tengine
    ## 开始安装
    echo -e "\033[1;31m **** 开始编译安装结合 tengine+modsecurity **** \033[0m"
     cd  ${DEPLOY_PATH}/tengine-${TENGINE_VERSION} && \
    ./configure --prefix=/usr/share/nginx \
       --with-http_lua_module \
       --with-luajit-lib=/usr/local/lib/ \
       --with-luajit-inc=/usr/local/include/luajit-2.1/ \
       --with-lua-inc=/usr/local/include/luajit-2.1/ --sbin-path=/usr/sbin/nginx  \
       --modules-path=/usr/lib64/nginx/modules  \
       --conf-path=/etc/nginx/nginx.conf  \
       --error-log-path=/var/log/nginx/error.log  \
       --http-log-path=/var/log/nginx/access.log  \
       --http-client-body-temp-path=/var/lib/nginx/tmp/client_body  \
       --http-proxy-temp-path=/var/lib/nginx/tmp/proxy  \
       --http-fastcgi-temp-path=/var/lib/nginx/tmp/fastcgi  \
       --http-uwsgi-temp-path=/var/lib/nginx/tmp/uwsgi  \
       --http-scgi-temp-path=/var/lib/nginx/tmp/scgi  \
       --pid-path=/var/run/nginx.pid  \
       --lock-path=/run/lock/subsys/nginx  \
       --user=nginx  \
       --group=nginx  \
       --with-file-aio  \
       --with-ipv6  \
       --with-http_auth_request_module  \
       --with-http_ssl_module  \
       --with-http_v2_module  \
       --with-http_realip_module  \
       --with-http_addition_module  \
       --with-http_xslt_module=dynamic  \
       --with-http_image_filter_module=dynamic  \
       --with-http_geoip_module=dynamic  \
       --with-http_sub_module  \
       --with-http_dav_module  \
       --with-http_flv_module  \
       --with-http_mp4_module  \
       --with-http_gunzip_module  \
       --with-http_gzip_static_module  \
       --with-http_random_index_module  \
       --with-http_secure_link_module  \
       --with-http_degradation_module  \
       --with-http_slice_module  \
       --with-http_stub_status_module  \
       --with-http_perl_module=dynamic  \
       --with-mail=dynamic  \
       --with-mail_ssl_module  \
       --with-pcre --with-pcre-jit  \
       --with-stream=dynamic  \
       --with-stream_ssl_module  \
       --with-stream_geoip_module=dynamic  \
       --with-google_perftools_module  \
       --with-debug  \
       --with-cc-opt="-O2 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector-strong --param=ssp-buffer-size=4 -grecord-gcc-switches -specs=/usr/lib/rpm/redhat/redhat-hardened-cc1 -m64 -mtune=generic "  \
       --with-ld-opt="-Wl,-z,relro -specs=/usr/lib/rpm/redhat/redhat-hardened-ld -Wl,-E"  \
       --add-module=../ModSecurity-nginx && make && make install
       ## add_dynamic 修改未 add-module
}

function modify_somebug(){
    ## 自动修复相关的 bug
    mkdir -p /var/lib/nginx/tmp/;
    cp ${DEPLOY_PATH}/ModSecurity/unicode.mapping /etc/nginx ;
    ln -sv `find / -type f -name "libprofiler.so*" | grep /usr/local/lib` /lib64/libprofiler.so.0
    ln -sv `find / -type f -name "libluajit-5.1.so*" | grep /usr/local/lib` /lib64/libluajit-5.1.so.2
    useradd -s /sbin/nologin -M nginx
}

install_pre_utils
install_gperftools
install_luaJit

get_common_modsecurity_conf
install_modsecurity
make_modsecurity_with_tengine
modify_somebug
