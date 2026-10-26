<!-- torch 2.14.1+cpu, pyrefly 1.4.0 hover, corpus torch__nn.LayerNorm.md:7-15 -->
This layer implements the operation as described in  
the paper `Layer Normalization <https://arxiv.org/abs/1607.06450>`__  
  
.. math:  
```  
y = \frac{x - \mathrm{E}[x]}{ \sqrt{\mathrm{Var}[x] + \epsilon}} * \gamma + \beta  
  
```  
The mean and standard-deviation are calculated over the last `D` dimensions, where `D`  