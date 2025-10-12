package main

import (
	"fmt"
	"github.com/rivo/tview"
)

type Password struct {
	form          *tview.Form
	changed       func(text string)
	valid         func(valid bool)
	value1        string
	value2        string
	formItemIndex int
	label2Ok      string
	label2Nok     string
}

func AddPasswordToForm(form *tview.Form, label string, value string, changed func(text string), valid func(valid bool)) {
	p := Password{
		form:          form,
		changed:       changed,
		valid:         valid,
		value1:        value,
		value2:        value,
		formItemIndex: form.GetFormItemCount(),
		label2Ok:      fmt.Sprintf("%s (repeat)", label),
		label2Nok:     fmt.Sprintf("%s (NO MATCH)", label),
	}
	form.AddPasswordField(label, value, 0, '*', func(text string) {
		p.value1 = text
		p.changedFunc()
	})
	form.AddPasswordField(p.label2Ok, value, 0, '*', func(text string) {
		p.value2 = text
		p.changedFunc()
	})
}

func (p *Password) changedFunc() {
	if p.value1 == p.value2 {
		p.changed(p.value1)
		p.valid(true)
		p.inputField(1).SetLabel(p.label2Ok)
	} else {
		p.changed("")
		p.valid(false)
		p.inputField(1).SetLabel(p.label2Nok)
	}
}

func (p *Password) inputField(index int) *tview.InputField {
	item := p.form.GetFormItem(p.formItemIndex + index)
	inputField, ok := item.(*tview.InputField)
	if !ok {
		panic("Internal Error: AddPasswordField does not add an InputField?")
	}
	return inputField
}
