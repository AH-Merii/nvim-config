<!-- huggingface_hub 2.3.0, pyrefly 1.4.0 hover, corpus huggingface_hub__HfApi.list_models.md:89-98,128-132 -->
Example:  
  
```python  
```python  
>>> from huggingface_hub import HfApi  
  
>>> api = HfApi()  
  
```  
# List all models  
# List models with 6B to 128B parameters  
```python  
>>> api.list_models(num_parameters="min:6B,max:128B", sort="likes")  
```  
```