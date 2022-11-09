mint 
+ token 通过调用cErc20Delegate部署后，可以通过当前token兑换处ctoken
+ cToken要先上市
+ mint




# 利率计算
[!https://img-blog.csdnimg.cn/d20cf9ce45604a858e749a3a9c05e267.webp?x-oss-process=image/watermark,type_d3F5LXplbmhlaQ,shadow_50,text_Q1NETiBAd29uZGVyQmxvY2s=,size_20,color_FFFFFF,t_70,g_se,x_16]
[!https://img-blog.csdnimg.cn/9dba9baeb5d94ec68a67a8e7b0ac0806.webp?x-oss-process=image/watermark,type_d3F5LXplbmhlaQ,shadow_50,text_Q1NETiBAd29uZGVyQmxvY2s=,size_20,color_FFFFFF,t_70,g_se,x_16]
存款利率计算
```存款利率 =（借款总额 * 借款利率）/ 存款总额```
存款额度计算
```新的存款总额 = 存款总额 +（存款总额 * 存款利率 * 时间）```
贷款额度
```新的贷款总额 = 贷款总额 +（贷款总额 * 贷款利率 * 时间）```