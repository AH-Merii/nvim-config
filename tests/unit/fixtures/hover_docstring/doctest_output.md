<!-- torch 2.14.1+cpu, pyrefly 1.4.0 hover, corpus torch__cat.md:36-52 -->
Example:  
  
```python  
>>> x = torch.randn(2, 3)  
>>> x  
```  
&nbsp;&nbsp;&nbsp;&nbsp;tensor([[ 0.6580, -1.0969, -0.4614],  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[-0.1034, -0.5790,  0.1497]])  
```python  
>>> torch.cat((x, x, x), 0)  
```  
&nbsp;&nbsp;&nbsp;&nbsp;tensor([[ 0.6580, -1.0969, -0.4614],  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[-0.1034, -0.5790,  0.1497],  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[ 0.6580, -1.0969, -0.4614],  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[-0.1034, -0.5790,  0.1497],  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[ 0.6580, -1.0969, -0.4614],  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[-0.1034, -0.5790,  0.1497]])  