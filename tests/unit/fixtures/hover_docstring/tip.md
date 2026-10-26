<!-- transformers 5.20.2, pyrefly 1.4.0 hover, corpus transformers__Trainer.md:7-19 -->
Args:  
&nbsp;&nbsp;&nbsp;&nbsp;model ([`PreTrainedModel`] or `torch.nn.Module`, *optional*):  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;The model to train, evaluate or use for predictions. If not provided, a `model_init` must be passed.  
  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<Tip>  
  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;[`Trainer`] is optimized to work with the [`PreTrainedModel`] provided by the library. You can still use  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;your own models defined as `torch.nn.Module` as long as they work the same way as the 🤗 Transformers  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;models.  
  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;</Tip>  
  
&nbsp;&nbsp;&nbsp;&nbsp;args ([`TrainingArguments`], *optional*):  